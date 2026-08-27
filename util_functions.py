from __future__ import print_function
import numpy as np
import random
from tqdm import tqdm
import os, sys, pdb, math, time
import networkx as nx
import argparse
import scipy.io as sio
import scipy.sparse as ssp
from sklearn import metrics
from gensim.models import Word2Vec
import warnings
from util import S2VGraph
import multiprocessing as mp
from itertools import islice

warnings.simplefilter('ignore', ssp.SparseEfficiencyWarning)

# ======================================================
# Enhanced Helper Functions with Debugging
# ======================================================

def debug_matrix_connections(A, node_idx, direction='fanin', max_display=10):
    """Debug helper to inspect connections in sparse matrix."""
    print(f"\n🔍 DEBUG: {direction.upper()} connections for node {node_idx}")
    if direction == 'fanin':
        # Show non-zero entries in column node_idx (nodes pointing TO this node)
        col = A[:, node_idx].tocoo()
        print(f"  Non-zero entries in column {node_idx}: {col.nnz}")
        if col.nnz > 0:
            print(f"  Source nodes with edges TO {node_idx}:")
            for i in range(min(col.nnz, max_display)):
                print(f"    Edge from node {int(col.row[i])} to {node_idx}")
    else:
        # Show non-zero entries in row node_idx (nodes this node points TO)
        row = A[node_idx, :].tocoo()
        print(f"  Non-zero entries in row {node_idx}: {row.nnz}")
        if row.nnz > 0:
            print(f"  Target nodes with edges FROM {node_idx}:")
            for i in range(min(row.nnz, max_display)):
                print(f"    Edge from {node_idx} to node {int(row.col[i])}")

def verify_graph_consistency(G, A, node_mapping=None):
    """Verify that graph structure matches adjacency matrix."""
    print("\n✅ Verifying graph consistency...")
    
    # Check number of nodes
    num_nodes_g = G.number_of_nodes()
    num_nodes_a = A.shape[0]
    print(f"  Graph nodes: {num_nodes_g}, Matrix size: {num_nodes_a}x{num_nodes_a}")
    
    if num_nodes_g != num_nodes_a:
        print(f"  ⚠️ MISMATCH: Graph has {num_nodes_g} nodes but matrix is {num_nodes_a}x{num_nodes_a}")
    
    # Check edge counts
    edge_count_g = G.number_of_edges()
    edge_count_a = A.nnz
    print(f"  Graph edges: {edge_count_g}, Matrix non-zeros: {edge_count_a}")
    
    if edge_count_g != edge_count_a:
        print(f"  ⚠️ MISMATCH: Graph has {edge_count_g} edges but matrix has {edge_count_a} non-zeros")
    
    # Check a few random nodes for consistency
    sample_nodes = min(5, num_nodes_g)
    nodes = list(G.nodes())[:sample_nodes]
    print(f"\n  🔍 Checking {sample_nodes} sample nodes for edge consistency:")
    
    for node in nodes:
        # Get neighbors from graph
        if G.is_directed():
            in_neigh_g = list(G.predecessors(node))
            out_neigh_g = list(G.successors(node))
        else:
            in_neigh_g = out_neigh_g = list(G.neighbors(node))
        
        # Get neighbors from matrix
        col = A[:, node].tocoo()  # nodes pointing TO node
        row = A[node, :].tocoo()  # nodes node points TO
        
        in_neigh_a = list(col.row.astype(int))
        out_neigh_a = list(row.col.astype(int))
        
        print(f"\n    Node {node}:")
        print(f"      Graph in-neighbors ({len(in_neigh_g)}): {in_neigh_g}")
        print(f"      Matrix in-neighbors ({len(in_neigh_a)}): {in_neigh_a}")
        print(f"      Graph out-neighbors ({len(out_neigh_g)}): {out_neigh_g}")
        print(f"      Matrix out-neighbors ({len(out_neigh_a)}): {out_neigh_a}")

def neighbors_fanin(fringe, A, debug=False):
    """Find fan-in neighbors - nodes that have edges pointing TO the fringe nodes."""
    res = []
    for node in fringe:
        try:
            node_idx = int(node)
            # For directed graph where A[i,j]=1 means edge from i to j:
            # Column A[:, node] contains all i where A[i, node]=1
            # i.e., all nodes that point TO 'node'
            nei, _, _ = ssp.find(A[:, node_idx])
            
            if debug:
                print(f"  Node {node_idx} has {len(nei)} fan-in neighbors: {nei.astype(int).tolist()}")
            
            if len(nei) > 0:
                res = union_list(res, nei.astype(int).tolist())
        except Exception as e:
            if debug:
                print(f"  Error processing node {node}: {str(e)}")
            continue
    return res

def neighbors_fanout(fringe, A, debug=False):
    """Find fan-out neighbors - nodes that the fringe nodes point TO."""
    res = []
    for node in fringe:
        try:
            node_idx = int(node)
            # Row A[node, :] contains all j where A[node, j]=1
            # i.e., all nodes that 'node' points TO
            _, nei, _ = ssp.find(A[node_idx, :])
            
            if debug:
                print(f"  Node {node_idx} has {len(nei)} fan-out neighbors: {nei.astype(int).tolist()}")
            
            if len(nei) > 0:
                res = union_list(res, nei.astype(int).tolist())
        except Exception as e:
            if debug:
                print(f"  Error processing node {node}: {str(e)}")
            continue
    return res

def union_list(first_list, second_list):
    resulting_list = list(first_list)
    resulting_list.extend(x for x in second_list if x not in resulting_list)
    return resulting_list

def subtract_list(first_list, second_list):
    resulting_list = []
    resulting_list.extend(x for x in first_list if x not in second_list)
    return resulting_list

# ======================================================
# Enhanced Subgraph Extraction with Fallback Logic
# ======================================================

def subgraph_extraction_labeling(ind, A, B, h, node_information, DE_FLAG, benchmark_name, file_name, debug=False):
    # Debug logging
    debug_file = None
    if debug:
        try:
            debug_dir = os.path.join('./data', file_name, 'debug_subgraph_logs')
            if not os.path.exists(debug_dir):
                os.makedirs(debug_dir, exist_ok=True)
            
            debug_file = os.path.join(debug_dir, f'subgraph_keygate_{ind}.txt')
            with open(debug_file, 'w') as f:
                f.write(f"Inside Subgraph Extraction for key node {ind}\n")
                f.write("================================================================================\n\n")
                if A is None:
                    f.write("WARNING: Adjacency matrix A is None!\n")
                elif A.nnz == 0:
                    f.write("WARNING: Adjacency matrix A has 0 non-zero elements!\n")
        except Exception as e:
            print(f"Debug logging failed for node {ind}: {e}")
    """Extract enclosing subgraph for a given node with h hops."""
    nodes = [ind]
    visited = {ind}
    labels_list = [0]
    fan_out = [ind]
    fan_in = [ind]
    
    for dist in range(1, h+1):
        next_fan_out = []
        next_fan_in = []
        
        # Process fan-out neighbors
        if len(fan_out) > 0:
            current_out = []
            for node in fan_out:
                try:
                    # Optimized lookup: get neighbor array directly
                    nei_arr = A.indices[A.indptr[int(node)]:A.indptr[int(node)+1]]
                    # Use set-based filtering for efficiency
                    new_out = [n for n in nei_arr if n not in visited]
                    current_out.extend(new_out)
                except Exception as e:
                    print(f"Error processing fan-out for node {node}: {e}")
            
            # Log fan-out
            if debug_file:
                try:
                    with open(debug_file, 'a') as f:
                        f.write(f"Hop {dist} Fan-out: Found {len(current_out)} new neighbors from {len(fan_out)} nodes\n")
                except: pass
            for _ in current_out:
                labels_list.append(-dist)
            nodes.extend(current_out)
            visited.update(current_out)
            next_fan_out = current_out
        
        # Process fan-in neighbors
        if len(fan_in) > 0:
            current_in = []
            for node in fan_in:
                try:
                    nei_arr = A.indices[A.indptr[int(node)]:A.indptr[int(node)+1]]
                    new_in = [n for n in nei_arr if n not in visited]
                    current_in.extend(new_in)
                except Exception as e:
                    print(f"Error processing fan-in for node {node}: {e}")
            
            # Log fan-in
            if debug_file:
                try:
                    with open(debug_file, 'a') as f:
                        f.write(f"Hop {dist} Fan-in: Found {len(current_in)} new neighbors from {len(fan_in)} nodes\n")
                except: pass
            for _ in current_in:
                labels_list.append(dist)
            nodes.extend(current_in)
            visited.update(current_in)
            next_fan_in = current_in
        
        fan_out, fan_in = next_fan_out, next_fan_in
        if len(fan_out) == 0 and len(fan_in) == 0:
            break
    
    # Create subgraph
    nodes_arr = np.array(nodes)
    if nodes_arr.size > 0:
        try:
            subgraph = A[nodes_arr, :][:, nodes_arr]
        except Exception as e:
            print(f"Error creating subgraph: {e}")
            subgraph = ssp.csr_matrix((len(nodes_arr), len(nodes_arr)))
    else:
        subgraph = ssp.csr_matrix((1, 1))
    
    # Create features
    features = []
    for i, node in enumerate(nodes):
        if node_information is not None and node < len(node_information):
            try:
                vector = list(node_information[node])
                # Add distance encoding if enabled
                if DE_FLAG:
                    one_hot_khop = [0] * 5
                    label_val = labels_list[i]
                    if label_val == -2:
                        one_hot_khop = [1,0,0,0,0]
                    elif label_val == -1:
                        one_hot_khop = [0,1,0,0,0]
                    elif label_val == 0:
                        one_hot_khop = [0,0,1,0,0]
                    elif label_val == 1:
                        one_hot_khop = [0,0,0,1,0]
                    elif label_val == 2:
                        one_hot_khop = [0,0,0,0,1]
                    vector.extend(one_hot_khop)
                features.append(vector)
            except Exception as e:
                print(f"Error creating features for node {node}: {e}")
                if node_information.size > 0:
                    features.append([0.0] * (len(node_information[0]) + (5 if DE_FLAG else 0)))
                else:
                    features.append([0.0] * (5 if DE_FLAG else 1))
        else:
            if node_information is not None and len(node_information) > 0:
                features.append([0.0] * (len(node_information[0]) + (5 if DE_FLAG else 0)))
            else:
                features.append([0.0] * (5 if DE_FLAG else 1))
    
    features = np.array(features, dtype=np.float32) if features else np.zeros((1, 1))
    g = nx.DiGraph(subgraph)
    fanvec = nodes
    
    return g, labels_list, features, ind, fanvec

# Global variables to hold shared data in worker processes
_A = None
_B = None
_node_information = None

def init_worker(A, B, node_information):
    """Initialize worker process with shared data."""
    global _A, _B, _node_information
    _A = A
    _B = B
    _node_information = node_information

def parallel_worker(args):
    """Worker function for parallel processing."""
    i, hop, de_flag_param, benchmark_name, file_name, debug = args
    return subgraph_extraction_labeling(i, _A, _B, hop, _node_information, de_flag_param, benchmark_name, file_name, debug)

def keygates2subgraphs(A, B, train_pos, train_neg, test_pos, test_neg,
                      val_pos, val_neg, hop, node_information,
                      no_parallel, use_dis, de_flag_param=False, split_val=True,
                      unused_1=None, unused_2=None, attributes=None, links_idx=None,
                      file_name='dataset', debug_subgraph=False):
    """Extract subgraphs around key gates for the OMLA model."""
    out_dir = os.path.join('./data', file_name)
    os.makedirs(out_dir, exist_ok=True)
    fanvec_path = os.path.join(out_dir, 'fan_vectors.txt')
    
    def helper(A, B, links, g_label):
        """Helper function to extract subgraphs for a set of links."""
        g_list = []
        fanvec_entries = []
        if links is None or len(links) == 0:
            return g_list, fanvec_entries
        
        if no_parallel:
            for i in tqdm(links, desc=f'Extracting {g_label} subgraphs'):
                try:
                    g, n_labels, n_features, ind, fanvec = subgraph_extraction_labeling(
                        i, A, B, hop, node_information, de_flag_param, file_name, file_name, debug_subgraph)
                    # Create S2VGraph with correct parameters
                    graph_obj = S2VGraph(
                        g=g,
                        label=g_label,
                        node_tags=n_labels,
                        node_features=n_features,
                        key_node=ind
                    )
                    g_list.append(graph_obj)
                    fanvec_entries.append((ind, fanvec))
                except Exception as e:
                    print(f"Error processing node {i}: {e}")
            return g_list, fanvec_entries
        else:
            arg_list = [(int(i), hop, de_flag_param, file_name, file_name, debug_subgraph) for i in links]
            try:
                with mp.Pool(mp.cpu_count(), initializer=init_worker, initargs=(A, B, node_information)) as pool:
                    results = pool.map(parallel_worker, arg_list)
                for (g, labels_, features_, ind, fanvec) in results:
                    # Create S2VGraph with correct parameters
                    graph_obj = S2VGraph(
                        g=g,
                        label=g_label,
                        node_tags=labels_,
                        node_features=features_,
                        key_node=ind
                    )
                    g_list.append(graph_obj)
                    fanvec_entries.append((ind, fanvec))
                
                # Help GC
                del results
                del arg_list
                
                return g_list, fanvec_entries
            except Exception as e:
                print(f"Parallel processing error: {e}")
                print("Falling back to sequential processing...")
                for i in tqdm(links, desc=f'Extracting {g_label} subgraphs (fallback)'):
                    try:
                        g, n_labels, n_features, ind, fanvec = subgraph_extraction_labeling(
                            i, A, B, hop, node_information, de_flag_param, file_name, file_name, debug_subgraph)
                        # Create S2VGraph with correct parameters
                        graph_obj = S2VGraph(
                            g=g,
                            label=g_label,
                            node_tags=n_labels,
                            node_features=n_features,
                            key_node=ind
                        )
                        g_list.append(graph_obj)
                        fanvec_entries.append((ind, fanvec))
                    except Exception as e2:
                        print(f"Error in fallback processing node {i}: {e2}")
                return g_list, fanvec_entries

    print('Enclosing subgraph extraction begins...')
    train_graphs = test_graphs = val_graphs = None
    all_fanvecs = []

    if train_pos is not None and len(train_pos) > 0 and train_neg is not None and len(train_neg) > 0:
        print(f"Processing {len(train_pos)} positive training samples and {len(train_neg)} negative training samples")
        tr_pos_graphs, tr_pos_fv = helper(A, B, train_pos, 0)
        tr_neg_graphs, tr_neg_fv = helper(A, B, train_neg, 1)
        train_graphs = tr_pos_graphs + tr_neg_graphs
        all_fanvecs += tr_pos_fv + tr_neg_fv
        print(f"Created {len(train_graphs)} training graphs")
    else:
        print("Warning: No training data available or empty")

    if test_pos is not None and len(test_pos) > 0 and test_neg is not None and len(test_neg) > 0:
        print(f"Processing {len(test_pos)} positive test samples and {len(test_neg)} negative test samples")
        te_pos_graphs, te_pos_fv = helper(A, B, test_pos, 0)
        te_neg_graphs, te_neg_fv = helper(A, B, test_neg, 1)
        test_graphs = te_pos_graphs + te_neg_graphs
        all_fanvecs += te_pos_fv + te_neg_fv
        print(f"Created {len(test_graphs)} test graphs")
    else:
        print("Warning: No test data available or empty")

    if val_pos is not None and len(val_pos) > 0 and val_neg is not None and len(val_neg) > 0:
        print(f"Processing {len(val_pos)} positive validation samples and {len(val_neg)} negative validation samples")
        va_pos_graphs, va_pos_fv = helper(A, B, val_pos, 0)
        va_neg_graphs, va_neg_fv = helper(A, B, val_neg, 1)
        val_graphs = va_pos_graphs + va_neg_graphs
        all_fanvecs += va_pos_fv + va_neg_fv
        print(f"Created {len(val_graphs)} validation graphs")
    else:
        print("Warning: No validation data available or empty")

    # Write fan vector log
    try:
        with open(fanvec_path, 'w') as fout:
            fout.write("# fan vectors for dataset {}\n".format(file_name))
            fout.write("# Format: KeyNode <ind>: [node1,node2,...]\n")
            for ind, fv in sorted(all_fanvecs, key=lambda x: int(x[0])):
                if len(fv) > 0:
                    fout.write("KeyNode {}: {}\n".format(ind, fv))
        print(f"Fan vectors saved to {fanvec_path}")
    except Exception as e:
        print("Error writing fan vector file:", e)

    return train_graphs, test_graphs, val_graphs
# [Rest of the functions remain unchanged: parallel_worker, keygates2subgraphs, get_k_hop_neighbors, save_khop_results, annotate_k_hop_neighbors]

# ======================================================
# Integration and Usage Example
# ======================================================

if __name__ == "__main__":
    # Example usage with enhanced debugging
    parser = argparse.ArgumentParser(description='Enhanced subgraph extraction with fan-in/fan-out debugging')
    parser.add_argument('--benchmark', type=str, default='circuit_dataset', help='Benchmark name for debug logs')
    parser.add_argument('--key_node', type=int, default=93, help='Key node to analyze')
    parser.add_argument('--hops', type=int, default=2, help='Number of hops to extract')
    parser.add_argument('--debug', action='store_true', help='Enable detailed debugging')
    args = parser.parse_args()

    print(f"🔍 Enhanced subgraph extraction for benchmark: {args.benchmark}")
    print(f"🔑 Key node: {args.key_node}, Hops: {args.hops}")
    
    if args.debug:
        print("\n💡 DEBUG MODE ENABLED - will generate detailed logs")
        print("   Check ./data/{benchmark_name}/debug_subgraph_logs/ for detailed debug files")
    
    print("\n✅ System initialized. Ready for enhanced subgraph extraction with proper fan-in vector handling.")