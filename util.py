import networkx as nx
import numpy as np
import random
import torch
from sklearn.model_selection import StratifiedKFold

class S2VGraph(object):
    __slots__ = ['g', 'key_node', 'keygate', 'label', 'node_tags', 'neighbors', 'num_nodes', 'node_features', 'x', 'edge_mat', 'max_neighbor']
    def __init__(self, g, label, node_tags=None, node_features=None, key_node=None):
        '''
            g: a networkx graph
            label: an integer graph label
            node_tags: a list of integer node tags
            node_features: a torch float tensor, one-hot representation of the tag that is used as input to neural nets
            key_node: index of the key node (center node of the subgraph)
            edge_mat: a torch long tensor, contain edge list, will be used to create torch sparse tensor
            neighbors: list of neighbors (without self-loop)
        '''
        self.key_node = key_node if key_node is not None else 0  # Default to 0 if not provided
        self.keygate = self.key_node
        self.label = label
        self.g = g
        self.node_tags = node_tags
        self.neighbors = []
        self.num_nodes = len(g.nodes())
        self.node_features = node_features

        # ✅ Convert node features to torch tensor
        if node_features is not None and len(node_features) > 0:
            self.node_features = torch.from_numpy(node_features).float()
        else:
            # Create default zero features if none provided
            self.node_features = torch.zeros((self.num_nodes, 1))
        
        self.x = self.node_features  # For PyTorch Geometric compatibility

        self.edge_mat = 0
        self.max_neighbor = 0
        self.neighbors = [[] for i in range(self.num_nodes)]

        for i, j in g.edges():
            self.neighbors[i].append(j)
            self.neighbors[j].append(i)

        degree_list = []
        for i in range(self.num_nodes):
            self.neighbors[i] = self.neighbors[i]
            degree_list.append(len(self.neighbors[i]))
        self.max_neighbor = max(degree_list) if degree_list else 0

        if g.number_of_edges() == 0:
            print("Yes we have 0 edges, i will add a self loop")
            g.add_edge(0, 0)

        edges = [list(pair) for pair in g.edges()]
        edges.extend([[i, j] for j, i in edges])
        deg_list = list(dict(g.degree(range(self.num_nodes))).values())
        self.edge_mat = torch.LongTensor(edges).transpose(0, 1)