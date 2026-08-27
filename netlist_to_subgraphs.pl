#!/usr/bin/env perl
#
# netlist_to_subgraph_full.pl
# Full OMLA-style netlist parser + node labeling (compatible with your TheCircuit.pm)
#
use strict;
use warnings;
use FindBin;
use Data::Dumper;
use List::Util qw(shuffle);
use lib $FindBin::Bin;  # use script's directory for module search
use theCircuit;
use File::Path qw(make_path);
use File::Spec;
use Getopt::Long;
use POSIX qw(strftime);
# ============================================
# GLOBAL ARRAYS FOR TRAIN/VAL/TEST SPLIT
# ============================================
my @tr   = ();   # training
my @va   = ();   # validation
my @te   = ();   # testing
# ============================================


# ------------------ Configuration ------------------
my $AGGRESSIVE_KEY_DETECTION = 1;    # 0 = conservative (KEYINPUT only), 1 = aggressive regex
my $MAX_DISTANCE_LOG = 5;            # compute BFS distances up to this (for debugging)
# ---------------------------------------------------

# Feature mapping (must match feat.txt sample: 11 entries)
my %features_map = (
    "PI"       => 0,
    "PO"       => 1,
    "KEYINPUT" => 2,
    "XNOR"     => 3,
    "XOR"      => 4,
    "AND"      => 5,
    "OR"       => 6,
    "NAND"     => 7,
    "NOR"      => 8,
    "INV"      => 9,
    "BUF"      => 10,
);

# module_map mapping for labels
my %module_map = ( "key0" => 0, "key1" => 1 );

# Aggressive regex (if enabled)
my $AGGR_RE = qr/(?:key.*?input|key_in|k_in|keyinput|kinput|key.*?bit|secret|lock|k_\d+|key_\d+)/i;

# Command-line args
my $circuit_name    = '';
my $input_file_path = '';

GetOptions(
    'f=s' => \$circuit_name,
    'i=s' => \$input_file_path,
) or die "Error in command line arguments\n";

unless ( defined $input_file_path && -d $input_file_path ) {
    die "Expect input directory of Verilog files via -i\n";
}
unless ( $circuit_name ) {
    die "Please specify -f circuit_name (used to create ./data/<circuit_name>)\n";
}

# Prepare output directories and files
mkdir "./data" unless -d "./data";
my $out_dir = "./data/$circuit_name";
make_path($out_dir) unless -d $out_dir;

open my $FH_LINK,        '>', "$out_dir/link.txt"         or die $!;
open my $FH_NODE_TE_POS, '>', "$out_dir/node_te_pos.txt"  or die $!;
open my $FH_NODE_TE_NEG, '>', "$out_dir/node_te_neg.txt"  or die $!;
open my $FH_NODE_TR_POS, '>', "$out_dir/node_tr_pos.txt"  or die $!;
open my $FH_NODE_TR_NEG, '>', "$out_dir/node_tr_neg.txt"  or die $!;
open my $FH_NODE_VA_POS, '>', "$out_dir/node_va_pos.txt"  or die $!;
open my $FH_NODE_VA_NEG, '>', "$out_dir/node_va_neg.txt"  or die $!;
open my $FH_CELL,        '>', "$out_dir/cell.txt"         or die $!;
open my $FH_COUNT,       '>', "$out_dir/count.txt"        or die $!;
open my $FH_FEAT,        '>', "$out_dir/feat.txt"         or die $!;
open my $FH_DEBUG,       '>', "$out_dir/debug_final.log"  or die $!;

# Read input files
opendir my $dh, $input_file_path or die "Cannot open $input_file_path: $!";
my @input_files = sort grep { !/^\./ && -f "$input_file_path/$_" } readdir $dh;
closedir $dh;

my $start_time = time();

# Utility subs
sub trim { my $s = shift // ''; $s =~ s/^\s+|\s+$//g; return $s; }

sub is_likely_key {
    my ($name) = @_;
    return 0 unless defined $name && length $name;
    my $n = $name;
    $n =~ s/\[\d+\]//g;
    $n =~ s/^PI_//i;
    # detect key, keyinput, KEYINPUT
    return 1 if $n =~ /^key/i || $n =~ /KEYINPUT/i;
    return 1 if $AGGRESSIVE_KEY_DETECTION && $n =~ $AGGR_RE;
    return 0;
}

sub extract_key_id {
    my ($name) = @_;
    return 0 unless defined $name;
    if ($name =~ /(?:keyinput|key|k)[^\d]*(\d+)/i) {
        return $1;
    }
    return 0;
}

# Determine key label based on gate type (priority-based)
# Logic locking semantics (CORRECTED):
#   - key0 (label=0): gates that need key=0 to function normally (NAND, OR, XOR)
#   - key1 (label=1): gates that need key=1 to function normally (AND, NOR, XNOR, INV)
sub get_key_label_by_gate_type {
    my ($gate_type, $fallback_keyid) = @_;
    
    if (defined $fallback_keyid) {
        # KeyID parity: even => key1 (label 1, negative), odd => key0 (label 0, positive)
        return ($fallback_keyid % 2 == 0) ? 'key1' : 'key0';
    }
    # Default: not a key
    else {
        return 'not_key';
    }
}

# BFS distances from a set of root nodes (by instance name)
# Returns hashref dist{instance_name} = distance
sub bfs_from_roots {
    my ($roots_ref, $the_circuit_ref) = @_;
    my %the_circuit = %{$the_circuit_ref};
    my %dist = ();
    my @queue = ();
    foreach my $r (@$roots_ref) {
        next unless exists $the_circuit{$r};
        $dist{$r} = 0;
        push @queue, $r;
    }
    while (@queue) {
        my $cur = shift @queue;
        my $d = $dist{$cur};
        # neighbors: fedbygates_inst (predecessors) and fwdgates_inst (successors)
        my @pred = $the_circuit{$cur}->get_fedbygates_inst();
        my @succ = $the_circuit{$cur}->get_fwdgates_inst();
        foreach my $nbr (@pred, @succ) {
            next unless defined $nbr;
            next unless exists $the_circuit{$nbr};
            next if exists $dist{$nbr};
            $dist{$nbr} = $d + 1;
            push @queue, $nbr;
        }
    }
    return \%dist;
}

# Main processing loop: each file in dataset dir
foreach my $input_file (@input_files) {
    print $FH_DEBUG "[" . strftime("%Y-%m-%d %H:%M:%S", localtime) . "] Processing $input_file\n";
    my $trial = 3;         # default training
    my $file_type = "training";
    if ( $input_file =~ /^Valid/i )  { $trial = 1; $file_type = "validation"; }
    if ( $input_file =~ /^Test/i )   { $trial = 2; $file_type = "test"; }
    if ( $input_file =~ /^Train/i )  { $trial = 3; $file_type = "training"; }

    # per-file structures
    my %the_circuit = ();
    my %gate_to_outputs = ();
    my %wire_to_gate_output = ();
    my @list_of_gates = ();
    my @Module_Inputs = ();
    my @Module_Outputs = ();
    my @Netlist_Inputs = ();
    my @Netlist_Outputs = ();
    my %Netlist_Inputs_Hash = ();
    my %Netlist_Outputs_Hash = ();
    my %keyinput_map = ();
    my $ml_count = 0;
    my $assign_count = 0;

    # Open file
    open my $IN, '<', "$input_file_path/$input_file" or do { print $FH_DEBUG "Cannot open $input_file: $!\n"; next; };

    # FIRST PASS: identify module, inputs, outputs and map gate outputs -> instance
    while (<$IN>) {
        my $line = $_;
        # module
        if ( $line =~ /^\s*module\s+(\w+)\b/ ) {
            # top module name if needed
        }
        # endmodule: store module IO
        elsif ( $line =~ /^\s*endmodule\b/ ) {
            @Netlist_Inputs  = @Module_Inputs;
            @Netlist_Outputs = @Module_Outputs;
            @Module_Inputs   = ();
            @Module_Outputs  = ();
        }
        # input single-line
        elsif ( $line =~ /^\s*input\s+(.*?);/ ) {
            my $s = $1; $s =~ s/^\s+|\s+$//g;
            my @found = split /\s*,\s*/, $s;
            push @Module_Inputs, @found;
        }
        # output single-line
        elsif ( $line =~ /^\s*output\s+(.*?);/ ) {
            my $s = $1; $s =~ s/^\s+|\s+$//g;
            my @found = split /\s*,\s*/, $s;
            push @Module_Outputs, @found;
        }
        # gate instance single-line (simple)
        elsif ( $line =~ /^\s*(\S+)\s+(\S+)\s*\((.*?)\)\s*;/ ) {
            my ($cell,$inst,$ports_str) = ($1,$2,$3);
            my @pairs = split /\s*,\s*/, $ports_str;
            my %local = ();
            foreach my $p (@pairs) {
                if ($p =~ /\.(\w+)\s*\(\s*(\S+)\s*\)/) { $local{$1} = $2; }
            }
            my @output_ports = qw(Y Z Q CO S QN ZN);
            foreach my $port (@output_ports) {
                if (exists $local{$port}) {
                    my $w = $local{$port};
                    $wire_to_gate_output{$w} = $inst;
                    push @{$gate_to_outputs{$inst}}, $w;
                }
            }
        }
    }
    print "DEBUG: PIs = @Netlist_Inputs\n";
    print "DEBUG: POs = @Netlist_Outputs\n";

    close $IN;

    # Normalize inputs: expand vectors like [7:0] NAME or NAME[3]
    my @expanded_inputs = ();
    foreach my $inn (@Netlist_Inputs) {
        next unless defined $inn;
        $inn = trim($inn);
        # leading vector declaration [7:0] NAME
        if ( $inn =~ /^\s*\[(\d+)\s*:\s*(\d+)\]\s*(\S+)/ ) {
            my ($s,$e,$name) = ($1,$2,$3);
            my $i = $s;
            if ($s > $e) { $i = $e; $e = $s; }
            while ($i <= $e) {
                my $w = "$name\[$i]";
                push @expanded_inputs, $w;
                $keyinput_map{$w} = 1 if is_likely_key($w);
                $i++;
            }
        }
        # NAME[3] style
        elsif ( $inn =~ /^(\S+\[\d+\])$/ ) {
            my $w = $1;
            push @expanded_inputs, $w;
            $keyinput_map{$w} = 1 if is_likely_key($w);
        }
        else {
            push @expanded_inputs, $inn;
            $keyinput_map{$inn} = 1 if is_likely_key($inn);
        }
    }
    @Netlist_Inputs = @expanded_inputs;
    %Netlist_Inputs_Hash = map { $_ => 1 } @Netlist_Inputs;
    %Netlist_Outputs_Hash = map { $_ => 1 } @Netlist_Outputs;
    # also add normalized forms to output hash
    foreach my $o (@Netlist_Outputs) { (my $n = $o) =~ s/\[\d+\]//g; $Netlist_Outputs_Hash{$n} = 1; }

    # CREATE PRIMARY INPUT NODES
    print $FH_DEBUG "Creating PI nodes for inputs: @Netlist_Inputs\n";
    foreach my $pi_name (@Netlist_Inputs) {
        my $pi_node_name = "PI_$pi_name";
        my @pi_outputs = ($pi_name);
        
        # Determine if this is a KEYINPUT
        my $processed = 'not_key';
        if ( is_likely_key($pi_name) || exists $keyinput_map{$pi_name} ) {
            my $kid = extract_key_id($pi_name);
            # For PI nodes, use KEYINPUT number as we don't have gate type yet
            $processed = ($kid % 2 == 0) ? 'key1' : 'key0';
        }
        
        my $pi_obj = theCircuit->new({
            name => $pi_node_name,
            inputs => [],
            outputs => \@pi_outputs,
            bool_func => 'PI',
            fedbygates => [],
            fedbygates_inst => [],
            fwdgates => [undef],
            fwdgates_inst => [undef],
            processed => $processed,
            count => $ml_count,
        });
        
        $the_circuit{$pi_node_name} = $pi_obj;
        push @list_of_gates, $pi_node_name;
        $wire_to_gate_output{$pi_name} = $pi_node_name;
        $gate_to_outputs{$pi_node_name} = \@pi_outputs;
        
        push @tr, $ml_count if $trial == 3;
        push @va, $ml_count if $trial == 1;
        push @te, $ml_count if $trial == 2;
        $ml_count++;
    }
    
    # CREATE PRIMARY OUTPUT NODES
    print $FH_DEBUG "Creating PO nodes for outputs: @Netlist_Outputs\n";
    foreach my $po_name (@Netlist_Outputs) {
        my $po_node_name = "PO_$po_name";
        my @po_inputs = ($po_name);
        
        my $po_obj = theCircuit->new({
            name => $po_node_name,
            inputs => \@po_inputs,
            outputs => [],
            bool_func => 'PO',
            fedbygates => [],
            fedbygates_inst => [],
            fwdgates => [],
            fwdgates_inst => [],
            processed => 'not_key',
            count => $ml_count,
        });
        
        $the_circuit{$po_node_name} = $po_obj;
        push @list_of_gates, $po_node_name;
        
        push @tr, $ml_count if $trial == 3;
        push @va, $ml_count if $trial == 1;
        push @te, $ml_count if $trial == 2;
        $ml_count++;
    }

    # Re-open file for second pass (create objects)
    open $IN, '<', "$input_file_path/$input_file" or die "Can't reopen $input_file: $!";

    # parse and create objects (assigns + gate instances)
    while (<$IN>) {
        my $line = $_;
        # skip comments
        next if $line =~ /^\s*\/\//;

        # assign statements
        if ( $line =~ /^\s*assign\s+(\S+)\s*=\s*(\S+)\s*;/ ) {
            my ($out,$in) = ($1,$2);
            my $modname = "assign_$assign_count";
            push @list_of_gates, $modname;
            my @ins = ($in);
            my @outs = ($out);
            my @fedby_t = ();
            my @fedby_n = ();

            # mark as KEYINPUT or PI
            if ( exists $Netlist_Inputs_Hash{$in} && is_likely_key($in) ) {
                push @fedby_t, "KEYINPUT";
                push @fedby_n, $in;
            } elsif ( exists $Netlist_Inputs_Hash{$in} ) {
                push @fedby_t, "PI";
                push @fedby_n, $in;
            } else {
                push @fedby_t, "PI";
                push @fedby_n, $in;
            }

            my $processed = 'not_key';
            if ( exists $keyinput_map{$in} || is_likely_key($in) ) {
                my $key_id = extract_key_id($in);
                # For BUF (assign), use gate-type-based labeling
                $processed = get_key_label_by_gate_type('BUF', $key_id);
            }

            my $obj = theCircuit->new({
                name => $modname,
                inputs => \@ins,
                outputs => \@outs,
                bool_func => 'BUF',
                fedbygates => \@fedby_t,
                fedbygates_inst => \@fedby_n,
                fwdgates => [undef],
                fwdgates_inst => [undef],
                processed => $processed,
                count => $ml_count,
            });
            $the_circuit{$modname} = $obj;
            $gate_to_outputs{$modname} = \@outs;

            push @tr, $ml_count if $trial == 3;
            push @va, $ml_count if $trial == 1;
            push @te, $ml_count if $trial == 2;
            $ml_count++; $assign_count++;
            next;
        }

        # handle multi-line gate instances: join until semicolon
        if ( $line =~ /\(/ && $line !~ /\)\s*;/ ) {
            my $multi = $line;
            while (<$IN>) {
                $multi .= $_;
                last if $_ =~ /\)\s*;/;
            }
            $line = $multi;
        }

        # gate instance full
        if ( $line =~ /^\s*(\S+)\s+(\S+)\s*\((.+?)\)\s*;/s ) {
            my ($cell,$inst,$ports_str) = ($1,$2,$3);
            my @pairs = split /\s*,\s*/, $ports_str;
            my %local = ();
            foreach my $p (@pairs) {
                if ($p =~ /\.(\w+)\s*\(\s*(\S+)\s*\)/) { $local{$1} = $2; }
            }

            my @current_ins = ();
            my @current_ins_inst = ();
            my @current_outs = ();

            # common input port names (safe superset)
            foreach my $p (qw(A B D E F S0 S1 C CI A0 A1 A2 A3 B0 B1 B2 B3 BN AN DN C C1 C2 CI A3 A0 A4 A1 A2 B3 B2 B1 B0 B0N C0)) {
                if ( defined $local{$p} ) {
                    push @current_ins, $local{$p};
                }
            }
            # other ports that sometimes are used
            foreach my $p (qw(S Z Y Q CO QN ZN)) {
                if ( defined $local{$p} ) { push @current_outs, $local{$p}; }
            }

            # fallback: if no outputs captured, try Y or Z etc.
            if (!@current_outs) {
                foreach my $p (qw(Y Z Q CO S ZN QN)) {
                    push @current_outs, $local{$p} if defined $local{$p};
                }
            }

            # Normalize bool func
            my $bool_fun = $cell;
            $bool_fun =~ s/\_\S+//g;
            $bool_fun =~ s/\d+\D*$//g;
            $bool_fun = uc($bool_fun);
            $bool_fun =~ s/_$//;
            $bool_fun = 'INV' if $bool_fun eq 'NOT';
            $bool_fun = 'BUF' if $bool_fun =~ /^(DFF|CLK)/;
            $bool_fun = 'XOR' if $bool_fun eq 'MUX';

            my $processed = 'not_key';
            # check inputs for KEYINPUT - use gate type for labeling
            foreach my $inw (@current_ins) {
                if ( is_likely_key($inw) || exists $keyinput_map{$inw} ) {
                    my $kid = extract_key_id($inw);
                    # Use gate-type-based labeling with fallback to KEYINPUT parity
                    $processed = get_key_label_by_gate_type($bool_fun, $kid);
                    print $FH_DEBUG "GATE $inst type=$bool_fun connected to $inw -> label=$processed\n";
                    last;
                }
            }

            my $obj = theCircuit->new({
                name => $inst,
                inputs => \@current_ins,
                outputs => \@current_outs,
                bool_func => $bool_fun,
                fedbygates => [],
                fedbygates_inst => [],
                fwdgates => [undef],
                fwdgates_inst => [undef],
                processed => $processed,
                count => $ml_count,
            });

            $the_circuit{$inst} = $obj;
            push @list_of_gates, $inst;
            $gate_to_outputs{$inst} = \@current_outs;

            # record mapping outputs -> this instance (for later wiring)
            foreach my $outw (@current_outs) {
                $wire_to_gate_output{$outw} = $inst;
            }

            push @tr, $ml_count if $trial == 3;
            push @va, $ml_count if $trial == 1;
            push @te, $ml_count if $trial == 2;
            $ml_count++;
            next;
        }
    } # end second pass
    close $IN;

    # THIRD PASS: Build fedbygates and fwdgates (connectivity)
    # For every gate, examine its inputs; if an input equals some gate's output, register fedby and fwd connections
    foreach my $inst ( @list_of_gates ) {
        next unless exists $the_circuit{$inst};
        my $obj = $the_circuit{$inst};
        my @inputs = $obj->get_inputs();
        my @fedby_types = ();
        my @fedby_inst  = ();
        foreach my $inw (@inputs) {
            my $normalized = $inw;
            $normalized =~ s/\[\d+\]//g;
            # if this input is driven by another gate
            if ( exists $wire_to_gate_output{$inw} ) {
                my $src_inst = $wire_to_gate_output{$inw};
                push @fedby_types, $the_circuit{$src_inst}->get_bool_func() || 'UNKNOWN';
                push @fedby_inst, $src_inst;
                # add forward pointer on src_inst
                my @fwd = $the_circuit{$src_inst}->get_fwdgates();
                my @fwd_inst = $the_circuit{$src_inst}->get_fwdgates_inst();
                push @fwd, uc($obj->get_bool_func());
                push @fwd_inst, $inst;
                $the_circuit{$src_inst}->set_fwdgates(\@fwd);
                $the_circuit{$src_inst}->set_fwdgates_inst(\@fwd_inst);
            } else {
                # If input is primary input
                if ( exists $Netlist_Inputs_Hash{$inw} || exists $Netlist_Inputs_Hash{$normalized} ) {
                    push @fedby_types, "PI";
                    push @fedby_inst, $inw;
                } else {
                    # unresolved net (could be wire assigned later), keep as raw net to resolve below
                    push @fedby_types, "NET";
                    push @fedby_inst, $inw;
                }
            }
        }
        # set fedby arrays
        $obj->set_fedbygates(\@fedby_types);
        $obj->set_fedbygates_inst(\@fedby_inst);
        $the_circuit{$inst} = $obj;
    }

    # Resolve NETs by searching other gate outputs (one more pass)
    foreach my $inst ( @list_of_gates ) {
        next unless exists $the_circuit{$inst};
        my $obj = $the_circuit{$inst};
        my @fedby_inst = $obj->get_fedbygates_inst();
        my @fedby_types = $obj->get_fedbygates();
        for my $i (0..$#fedby_inst) {
            my $entry = $fedby_inst[$i];
            if (defined $entry && $entry ne 'NET') {
                next;
            }
            my $candidate = $fedby_inst[$i];
            # attempt to find gate which has this net as an output
            foreach my $g ( @list_of_gates ) {
                next unless exists $the_circuit{$g};
                my @gouts = $the_circuit{$g}->get_outputs();
                foreach my $o (@gouts) {
                    if (!defined $candidate) { next; }
                    (my $c_norm = $candidate) =~ s/\[\d+\]//g;
                    (my $o_norm = $o) =~ s/\[\d+\]//g;
                    if ( $c_norm eq $o_norm ) {
                        $fedby_inst[$i] = $g;
                        $fedby_types[$i] = $the_circuit{$g}->get_bool_func();
                        # add forward pointer
                        my @fwd = $the_circuit{$g}->get_fwdgates();
                        my @fwd_inst = $the_circuit{$g}->get_fwdgates_inst();
                        push @fwd, $obj->get_bool_func();
                        push @fwd_inst, $inst;
                        $the_circuit{$g}->set_fwdgates(\@fwd);
                        $the_circuit{$g}->set_fwdgates_inst(\@fwd_inst);
                        last;
                    }
                }
            }
        }
        $obj->set_fedbygates_inst(\@fedby_inst);
        $obj->set_fedbygates(\@fedby_types);
        $the_circuit{$inst} = $obj;
    }

    # Connect PO nodes to gates that drive them
    foreach my $inst ( @list_of_gates ) {
        next unless exists $the_circuit{$inst};
        my $obj = $the_circuit{$inst};
        next unless $obj->get_bool_func() eq 'PO';  # Only process PO nodes
        
        my @po_inputs = $obj->get_inputs();
        my @fedby_types = ();
        my @fedby_inst = ();
        
        foreach my $po_in (@po_inputs) {
            # Find the gate that outputs this wire
            if ( exists $wire_to_gate_output{$po_in} ) {
                my $src_inst = $wire_to_gate_output{$po_in};
                next if $src_inst eq $inst;  # Skip self-reference
                
                if ( exists $the_circuit{$src_inst} ) {
                    push @fedby_types, $the_circuit{$src_inst}->get_bool_func();
                    push @fedby_inst, $src_inst;
                    
                    # Add forward pointer from source gate to this PO
                    my @fwd = $the_circuit{$src_inst}->get_fwdgates();
                    my @fwd_inst = $the_circuit{$src_inst}->get_fwdgates_inst();
                    push @fwd, 'PO';
                    push @fwd_inst, $inst;
                    $the_circuit{$src_inst}->set_fwdgates(\@fwd);
                    $the_circuit{$src_inst}->set_fwdgates_inst(\@fwd_inst);
                }
            } else {
                # PO input might be a normalized name
                (my $po_in_norm = $po_in) =~ s/\[\d+\]//g;
                foreach my $g ( @list_of_gates ) {
                    next unless exists $the_circuit{$g};
                    next if $the_circuit{$g}->get_bool_func() eq 'PO';  # Skip other PO nodes
                    my @gouts = $the_circuit{$g}->get_outputs();
                    foreach my $o (@gouts) {
                        (my $o_norm = $o) =~ s/\[\d+\]//g;
                        if ( $o_norm eq $po_in_norm ) {
                            push @fedby_types, $the_circuit{$g}->get_bool_func();
                            push @fedby_inst, $g;
                            
                            # Add forward pointer
                            my @fwd = $the_circuit{$g}->get_fwdgates();
                            my @fwd_inst = $the_circuit{$g}->get_fwdgates_inst();
                            push @fwd, 'PO';
                            push @fwd_inst, $inst;
                            $the_circuit{$g}->set_fwdgates(\@fwd);
                            $the_circuit{$g}->set_fwdgates_inst(\@fwd_inst);
                            last;
                        }
                    }
                }
            }
        }
        
        $obj->set_fedbygates(\@fedby_types);
        $obj->set_fedbygates_inst(\@fedby_inst);
        $the_circuit{$inst} = $obj;
    }

    # Now detect key gates (those whose fedby includes KEYINPUT) and gather all key-gates
    # This pass re-labels gates based on their actual gate type (priority-based)
    my @key_gates = ();
    foreach my $inst ( @list_of_gates ) {
        next unless exists $the_circuit{$inst};
        my $obj = $the_circuit{$inst};
        my @fedby_inst = $obj->get_fedbygates_inst();
        my $gate_type = $obj->get_bool_func() || 'BUF';
        
        foreach my $inp (@fedby_inst) {
            next unless defined $inp;
            (my $clean_inp = $inp) =~ s/^PI_//i;
            # if the predecessor is a key input net
            if ( is_likely_key($inp) || exists $keyinput_map{$inp} || exists $keyinput_map{$clean_inp} ) {
                my $kid = extract_key_id($inp);
                
                # Use gate-type-based labeling
                my $proc = get_key_label_by_gate_type($gate_type, $kid);
                $obj->set_processed($proc);
                $the_circuit{$inst} = $obj;
                push @key_gates, $inst;
                print $FH_DEBUG "KEY GATE FOUND: $inst (type=$gate_type) fed by $inp -> $proc\n";
                last;
            }
        }
    }

    # Compute BFS distances from all key-gates (for debugging and possible future use)
    my $dist_ref = {};
    if (@key_gates) {
        $dist_ref = bfs_from_roots(\@key_gates, \%the_circuit);
        # Print summary distances for debug
        print $FH_DEBUG "BFS DISTANCES (sample up to distance $MAX_DISTANCE_LOG):\n";
        my %count_by_dist = ();
        foreach my $k (keys %{$dist_ref}) {
            my $d = $dist_ref->{$k};
            $count_by_dist{$d}++;
        }
        foreach my $d (sort { $a <=> $b } keys %count_by_dist) {
            print $FH_DEBUG "  dist $d : $count_by_dist{$d} nodes\n";
        }
    } else {
        print $FH_DEBUG "No key-gates detected in file $input_file\n";
    }

    # Build reverse mapping instance->count (for writing edges with numeric ids)
    my %inst_to_count = ();
    foreach my $inst ( @list_of_gates ) {
        next unless exists $the_circuit{$inst};
        $inst_to_count{$inst} = $the_circuit{$inst}->get_count();
    }

    # Now produce outputs: features, link, node label files, cell, count
    # Prepare dataset split maps
    my %is_tr = map { $_ => 1 } @tr;
    my %is_va = map { $_ => 1 } @va;
    my %is_te = map { $_ => 1 } @te;

    foreach my $inst ( @list_of_gates ) {
        next unless exists $the_circuit{$inst};
        my $obj = $the_circuit{$inst};
        my $count = $obj->get_count();
        my $name = $obj->get_name();
        my $gate_type = uc($obj->get_bool_func() || 'BUF');
        $gate_type =~ s/\d+$//;
        $gate_type =~ s/_$//;
        $gate_type = 'INV' if $gate_type eq 'NOT';
        $gate_type = 'BUF' if $gate_type =~ /^(DFF|CLK)/;
        $gate_type = 'XOR' if $gate_type eq 'MUX';

        # Build 11-length feature vector (matching your sample)
        my @features_array = (0) x 11;
        if ( exists $features_map{$gate_type} ) {
            $features_array[ $features_map{$gate_type} ] = 1;
        } else {
            # default to BUF (index 10)
            $features_array[ $features_map{"BUF"} ] = 1;
        }

        # PI feature: if any fedby is PI (or the fedby_inst contains an input net)
        my @fedby_types = $obj->get_fedbygates();
        my @fedby_inst = $obj->get_fedbygates_inst();
        my %fedby_type_map = map { $_ => 1 } @fedby_types;
        if ( exists $fedby_type_map{"PI"} ) {
            $features_array[ $features_map{"PI"} ] = 1;
        } else {
            # also check if any input is directly a top-level PI
            foreach my $i ($obj->get_inputs()) {
                (my $n = $i) =~ s/\[\d+\]//g;
                if ( exists $Netlist_Inputs_Hash{$i} || exists $Netlist_Inputs_Hash{$n} ) {
                    $features_array[ $features_map{"PI"} ] = 1;
                    last;
                }
            }
        }

        # KEYINPUT feature: if fedby includes KEYINPUT or any input name matches KEYINPUT pattern
        if ( exists $fedby_type_map{"KEYINPUT"} ) {
            $features_array[ $features_map{"KEYINPUT"} ] = 1;
        } else {
            foreach my $i ($obj->get_inputs()) {
                if ( is_likely_key($i) ) {
                    $features_array[ $features_map{"KEYINPUT"} ] = 1;
                    last;
                }
            }
        }

        # PO feature: if any outputs map to top-level outputs
        foreach my $out ($obj->get_outputs()) {
            (my $nrm = $out) =~ s/\[\d+\]//g;
            if ( exists $Netlist_Outputs_Hash{$out} || exists $Netlist_Outputs_Hash{$nrm} ) {
                $features_array[ $features_map{"PO"} ] = 1;
                last;
            }
        }

        # Write features (exact same format as your sample: 11 whitespace-separated 0/1)
        print $FH_FEAT join(' ', @features_array) . "\n";

        # label determination (matching reference labeling logic)
        my $module_name = $obj->get_processed();
        my $label = 2; # default: not a key-gate
        if ( defined $module_name ) {
            if ( exists $module_map{$module_name} ) {
                $label = $module_map{$module_name};
            }
            elsif ( $module_name =~ /key0/i || $module_name eq '0' ) {
                $label = 0; # key-gate with label 0 (positive)
            }
            elsif ( $module_name =~ /key1/i || $module_name eq '1' ) {
                $label = 1; # key-gate with label 1 (negative)
            }
            else {
                $label = 2; # not a key-gate
            }
        }

        # write node label files according to dataset split ($trial: 3=Train, 1=Valid, 2=Test)
        if ( $trial == 3 ) {
            print $FH_NODE_TR_POS "$count\n" if $label == 0;
            print $FH_NODE_TR_NEG "$count\n" if $label == 1;
        } elsif ( $trial == 1 ) {
            print $FH_NODE_VA_POS "$count\n" if $label == 0;
            print $FH_NODE_VA_NEG "$count\n" if $label == 1;
        } elsif ( $trial == 2 ) {
            print $FH_NODE_TE_POS "$count\n" if $label == 0;
            print $FH_NODE_TE_NEG "$count\n" if $label == 1;
        }

        # write cell and count (sanitize name: replace spaces with underscores to keep exactly 5 columns)
        (my $cell_name = $name) =~ s/ /_/g;
        print $FH_CELL "$count $cell_name from file $input_file\n";
        print $FH_COUNT "$count\n";
    }

    # Write links: for each gate, write edges to its forward-connected gate counts
    foreach my $inst ( @list_of_gates ) {
        next unless exists $the_circuit{$inst};
        my $obj = $the_circuit{$inst};
        my $src_count = $obj->get_count();
        my @fwd_inst = $obj->get_fwdgates_inst();
        foreach my $dst (@fwd_inst) {
            next unless defined $dst;
            next if $dst eq 'undef' || $dst eq 'PO';
            if ( exists $the_circuit{$dst} ) {
                my $dst_count = $the_circuit{$dst}->get_count();
                print $FH_LINK "$src_count $dst_count\n";
            }
        }
        # self-loop for PO nodes (if any outputs are top-level outputs)
        foreach my $out ($obj->get_outputs()) {
            (my $nrm = $out) =~ s/\[\d+\]//g;
            if ( exists $Netlist_Outputs_Hash{$out} || exists $Netlist_Outputs_Hash{$nrm} ) {
                print $FH_LINK "$src_count $src_count\n";
                last;
            }
        }
    }

    print $FH_DEBUG "Completed processing $input_file: gates=" . scalar(keys %the_circuit) . " key_gates=" . scalar(@key_gates) . "\n\n";

    # Clear per-file lists for next file
    @list_of_gates = ();
    %the_circuit = ();
    %gate_to_outputs = ();
    %wire_to_gate_output = ();
    %keyinput_map = ();
    @tr = (); @va = (); @te = ();
} # end foreach file

# Close filehandles
close $FH_LINK;
close $FH_NODE_TE_POS;
close $FH_NODE_TE_NEG;
close $FH_NODE_TR_POS;
close $FH_NODE_TR_NEG;
close $FH_NODE_VA_POS;
close $FH_NODE_VA_NEG;
close $FH_CELL;
close $FH_COUNT;
close $FH_FEAT;
close $FH_DEBUG;

my $run_time = time() - $start_time;
print STDERR "Program completed in $run_time sec\n";
exit 0;