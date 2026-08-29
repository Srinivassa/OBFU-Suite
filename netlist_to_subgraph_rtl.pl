#!/usr/bin/env perl
#
# netlist_to_subgraph_rtl.pl
# Full RTL-level netlist parser with support for datapath operators
# Supports: MUX, DEMUX, ADD, MUL, SUB, REG, LATCH + standard gate-level
#
use strict;
use warnings;
use FindBin;
use Data::Dumper;
use List::Util qw(shuffle);
use lib $FindBin::Bin;
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

# ------------------ Configuration ------------------
my $AGGRESSIVE_KEY_DETECTION = 1;    # 0 = conservative (KEYINPUT only), 1 = aggressive regex
my $MAX_DISTANCE_LOG = 5;            # compute BFS distances up to this (for debugging)

my %features_map = (
    "PI"     => 0,  # Normal primary input
    "PO"     => 1,  # Primary output
    "KEY_PI" => 2,  # Only a real key primary-input port
    "MUX"    => 3,  # Key-controlled selector
    "ADD"    => 4,  # fp_add
    "SUB"    => 5,  # fp_sub
    "MUL"    => 6,  # fp_mul
);

# module_map mapping for labels
my %module_map = ( "key0" => 0, "key1" => 1 );

# Aggressive regex (if enabled)
my $AGGR_RE = qr/(?:key.*?input|key_in|k_in|keyinput|kinput|key.*?bit|secret|lock|k_?\d+|key_?\d+)/i;

my $circuit_name    = '';
my $input_file_path = '';
my $key_string      = ''; # 16-bit binary string

GetOptions(
    'f=s'   => \$circuit_name,
    'i=s'   => \$input_file_path,
    'key=s' => \$key_string,
) or die "Error in command line arguments\n";

unless ( defined $input_file_path && -d $input_file_path ) {
    die "Expect input directory of Verilog files via -i\n";
}
unless ( $circuit_name ) {
    die "Please specify -f circuit_name (used to create ./data/<circuit_name>)\n";
}

# Read input files
opendir my $dh, $input_file_path or die "Cannot open $input_file_path: $!";
my @input_files = sort grep { !/^\./ && -f "$input_file_path/$_" } readdir $dh;
closedir $dh;

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

my $start_time = time();

# Utility subs
sub trim { my $s = shift // ''; $s =~ s/^\s+|\s+$//g; return $s; }

sub is_likely_key {
    my ($name) = @_;
    return 0 unless defined $name && length $name;
    my $n = $name;
    $n =~ s/\[\d+\]//g;
    # Case-insensitive detection for KEYINPUT or Keyinput
    return 1 if $n =~ /keyinput/i;
    # RTL vector ports are commonly declared as simply "key", then used as
    # key[0], key[1], ... in expressions.
    return 1 if $n =~ /^key$/i;
    # optional aggressive detection
    return 1 if $AGGRESSIVE_KEY_DETECTION && $n =~ $AGGR_RE;
    return 0;
}

sub normalize_wire {
    my ($w) = @_;
    return '' unless defined $w;
    $w =~ s/\[.*?\]//g;
    return $w;
}

# Return 0/1 key bit for a KEYINPUT select wire; undef if not a key wire.
sub mux_select_key_bit {
    my ($select_wire, $file_key_string) = @_;
    my $raw = trim($select_wire);
    my $sw = normalize_wire($raw);
    return undef unless is_likely_key($sw);

    # Verilog vector syntax uses LSB at index 0: key[0] is the rightmost
    # character of a binary key string such as 2'b10.  KEYINPUT1 naming,
    # on the other hand, is treated as one-based from the left.
    if ( $raw =~ /\[(\d+)\]/ ) {
        my $bit_index = $1;
        return undef unless defined $file_key_string
                         && length($file_key_string) > $bit_index;
        my $bit = substr( $file_key_string, length($file_key_string) - 1 - $bit_index, 1 );
        return ( $bit eq '1' ) ? 1 : 0;
    }

    my ($kid) = ($raw =~ /(?:KEYINPUT|Keyinput|k_?)(\d+)/i);
    return undef unless defined $kid && $kid >= 1;
    if ( defined $file_key_string && length($file_key_string) >= $kid ) {
        my $bit = substr( $file_key_string, $kid - 1, 1 );
        return ( $bit eq '1' ) ? 1 : 0;
    }
    return undef;
}

# Return a stable one-based identifier for either key[0] / key[1] syntax or
# KEYINPUT1 / KEYINPUT2 syntax.  This is used only to emit one label per key.
sub key_id_from_select_wire {
    my ($select_wire) = @_;
    my $raw = trim($select_wire);
    return undef unless is_likely_key( normalize_wire($raw) );
    return $1 + 1 if $raw =~ /\[(\d+)\]/;
    my ($kid) = ($raw =~ /(?:KEYINPUT|Keyinput|k_?)(\d+)/i);
    return $kid if defined $kid && $kid >= 1;
    return undef;
}

sub resolve_inst_for_wire {
    my ( $wire, $wire_to_module_output_ref ) = @_;
    my $w = normalize_wire($wire);
    return undef unless length $w;
    return $wire_to_module_output_ref->{$w} if exists $wire_to_module_output_ref->{$w};
    return undef;
}

sub resolve_src_count_for_wire {
    my ( $wire, $wire_to_module_output_ref, $circuit_ref, $list_ref ) = @_;
    my $src_inst = resolve_inst_for_wire( $wire, $wire_to_module_output_ref );
    if ( defined $src_inst && exists $circuit_ref->{$src_inst} ) {
        return $circuit_ref->{$src_inst}->get_count();
    }
    my $w = normalize_wire($wire);
    foreach my $g ( @{$list_ref} ) {
        next unless exists $circuit_ref->{$g};
        my $obj = $circuit_ref->{$g};
        next unless uc( $obj->get_bool_func() || '' ) eq 'PI';
        foreach my $out ( $obj->get_outputs() ) {
            return $obj->get_count() if normalize_wire($out) eq $w;
        }
    }
    return undef;
}

sub consumers_of_wire {
    my ( $wire, $list_ref, $circuit_ref ) = @_;
    my $w = normalize_wire($wire);
    return () unless length $w;
    my @dst_counts = ();
    foreach my $inst ( @{$list_ref} ) {
        next unless exists $circuit_ref->{$inst};
        my $obj = $circuit_ref->{$inst};
        foreach my $in_raw ( $obj->get_inputs() ) {
            if ( normalize_wire($in_raw) eq $w ) {
                push @dst_counts, $obj->get_count();
                last;
            }
        }
    }
    return @dst_counts;
}

# Ground-truth labels are taken only from the supplied key string.
# Never infer a key label from a gate/module type or a key-index parity.
sub get_key_label_by_key_bit {
    my ($key_bit) = @_;
    return 'key0' if defined $key_bit && $key_bit == 0;
    return 'key1' if defined $key_bit && $key_bit == 1;
    return 'not_key';
}

# BFS distances from a set of root nodes
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
        my @pred = $the_circuit{$cur}->get_fedby_modules_inst();
        my @succ = $the_circuit{$cur}->get_fwd_modules_inst();
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

# Global node counter - MUST be outside the per-file loop so IDs are unique across all files
my $ml_global_count = 0;

# Main processing loop
foreach my $input_file (@input_files) {
    print $FH_DEBUG "[" . strftime("%Y-%m-%d %H:%M:%S", localtime) . "] Processing $input_file\n";
    my $trial = 3;
    my $file_type = "training";
    if ( $input_file =~ /^Valid/i )  { $trial = 1; $file_type = "validation"; }
    if ( $input_file =~ /^Test/i )   { $trial = 2; $file_type = "test"; }
    if ( $input_file =~ /^Train/i )  { $trial = 3; $file_type = "training"; }

    # Dynamic file-based key extraction
    # Dynamic file-based key extraction - Scan for any string of at least 16 binary bits
    my $file_key_string = $key_string; 
    if ( $input_file =~ /([01]{16,})/ ) {
        $file_key_string = $1;
        print $FH_DEBUG "Found 16-bit key string: $file_key_string in filename: $input_file\n";
    } else {
        print $FH_DEBUG "WARNING: No 16-bit key found in filename: $input_file. Using default: $file_key_string\n";
    }

    # per-file structures
    my %the_circuit = ();
    my %module_to_outputs = ();
    my %wire_to_module_output = ();
    my @list_of_modules = ();
    my @Module_Inputs = ();
    my @Module_Outputs = ();
    my @Netlist_Inputs = ();
    my @Netlist_Outputs = ();
    my %Netlist_Inputs_Hash = ();
    my %Netlist_Outputs_Hash = ();
    my %keyinput_map = ();
    my $top_module_io_captured = 0;
    my $first_module_seen = 0;
    my $in_top_module = 0;
    my $ml_count = $ml_global_count;  # Start from global count, not 0
    my $assign_count = 0;

    # Open file
    open my $IN, '<', "$input_file_path/$input_file" or do { print $FH_DEBUG "Cannot open $input_file: $!\n"; next; };

    # FIRST PASS: identify module, inputs, outputs, AND internal key ground truth
    while (<$IN>) {
        my $line = $_;
        
        # Check for internal key ground truth in comments (Priority 1)
        if ( $line =~ /keyinput\s*:\s*([01]+)/i || $line =~ /Correct\s+key\s*:\s*\d+'b([01]+)/i ) {
            $file_key_string = $1 || $2;
            print $FH_DEBUG "Found INTERNAL Key Ground Truth: $file_key_string in $input_file\n";
        }
        
        # Continue only a genuine multi-line module instance.  In particular,
        # do not consume a module header/port declaration while looking for an
        # instance terminator; doing so loses all PI/PO declarations.
        if ( $line =~ /^\s*(?!module\b|function\b|task\b)\w+\s+\w+\s*\(/
             && $line !~ /\)\s*;/ ) {
            my $multi = $line;
            while (<$IN>) {
                $multi .= $_;
                last if $_ =~ /\)\s*;/;
            }
            $line = $multi;
        }

        if ( $line =~ /^\s*module\s+(\w+)\b/ ) {
            # The first module is the circuit under analysis.  Helper modules
            # (fp_add/fp_sub/fp_mul) must not replace its primary I/O list.
            if ( !$first_module_seen ) {
                $first_module_seen = 1;
                $in_top_module = 1;
            }
        }
        elsif ( $line =~ /^\s*endmodule\b/ ) {
            # Keep the I/O of the first (top-level) module.  Later endmodule
            # blocks belong to fp_add/fp_sub/fp_mul definitions and must not
            # overwrite the top-level circuit interface.
            if ( !$top_module_io_captured ) {
                @Netlist_Inputs  = @Module_Inputs;
                @Netlist_Outputs = @Module_Outputs;
                $top_module_io_captured = 1;
            }
            $in_top_module = 0;
            @Module_Inputs   = ();
            @Module_Outputs  = ();
        }
        elsif ( $line =~ /^\s*(input|output|wire|reg|inout)\s+(.*?);/ ) {
            my $type = $1;
            my $s = $2; $s =~ s/^\s+|\s+$//g;
            # Fix: strip bit-widths like [31:0]
            $s =~ s/\[.*?\]//g;
            my @found = split /\s*,\s*/, $s;
            foreach my $f (@found) {
                my $clean = trim($f);
                $clean =~ s/^(wire|reg|input|output)\s+//;
                if ($type eq 'input') {
                    push @Module_Inputs, $clean;
                    push @Netlist_Inputs, $clean if $in_top_module;
                }
                if ($type eq 'output') {
                    push @Module_Outputs, $clean;
                    push @Netlist_Outputs, $clean if $in_top_module;
                }
            }
        }
        elsif ( $line =~ /^\s*(\S+)\s+(\S+)\s*\((.*?)\)\s*;/s ) {
            my ($cell,$inst,$ports_str) = ($1,$2,$3);
            # Skip module declaration line to avoid it becoming a node
            next if $cell eq 'module' || $cell eq 'endmodule';
            my @pairs = split /\s*,\s*/, $ports_str;
            my %local = ();
            foreach my $p (@pairs) {
                if ($p =~ /\.(\w+)\s*\(\s*(\S+)\s*\)/) { $local{$1} = $2; }
            }
            # Comprehensive RTL output port detection
            my @output_ports = qw(Y Z Q CO S QN ZN result out output sum product diff quotient res z zout q qq dout dataout);
            foreach my $port (@output_ports) {
                if (exists $local{$port}) {
                    my $w = $local{$port};
                    $w =~ s/\[.*?\]//g; # Clean name
                    $wire_to_module_output{$w} = $inst;
                    push @{$module_to_outputs{$inst}}, $w;
                }
            }
        }
    }
    # Final name cleaning for PIs/POs
    foreach (@Netlist_Inputs) { $_ =~ s/\[.*?\]//g; $_ =~ s/^(wire|reg|input|output)\s+//; $_ = trim($_); }
    foreach (@Netlist_Outputs) { $_ =~ s/\[.*?\]//g; $_ =~ s/^(wire|reg|input|output)\s+//; $_ = trim($_); }
    print $FH_DEBUG "PIs = @Netlist_Inputs\n";
    print $FH_DEBUG "POs = @Netlist_Outputs\n";
    close $IN;

    # Normalize inputs: expand vectors
    my @expanded_inputs = ();
    foreach my $inn (@Netlist_Inputs) {
        next unless defined $inn;
        $inn = trim($inn);
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
    foreach my $o (@Netlist_Outputs) { (my $n = $o) =~ s/\[\d+\]//g; $Netlist_Outputs_Hash{$n} = 1; }

    # CREATE PRIMARY INPUT NODES
    print $FH_DEBUG "Creating PI nodes for inputs: @Netlist_Inputs\n";
    foreach my $pi_name (@Netlist_Inputs) {
        my $pi_node_name = "PI_$pi_name";
        my @pi_outputs = ($pi_name);
        
        my $processed = 'not_key';
        if ( is_likely_key($pi_name) || exists $keyinput_map{$pi_name} ) {
            my ($kid) = ($pi_name =~ /(?:KEYINPUT|K|k_?)(\d+)/i);
            $kid = 0 unless defined $kid;
            
            # Use provided key string if available (1-indexed matching Keyinput1..16)
            if ($file_key_string && length($file_key_string) >= 16) {
                my $bit = substr($file_key_string, $kid-1, 1);
                $processed = ($bit eq '1') ? 'key1' : 'key0';
            } else {
                # Ensure we don't crash, but log a specific marker
                $processed = 'key_mismatch'; 
            }
        }
        
        my $pi_obj = theCircuit->new({
            name => $pi_node_name,
            inputs => [],
            outputs => \@pi_outputs,
            bool_func => 'PI',
            fedby_modules => [],
            fedby_modules_inst => [],
            fwd_modules => [undef],
            fwd_modules_inst => [undef],
            processed => $processed,
            count => $ml_count,
        });
        
        $the_circuit{$pi_node_name} = $pi_obj;
        push @list_of_modules, $pi_node_name;
        $wire_to_module_output{$pi_name} = $pi_node_name;
        $module_to_outputs{$pi_node_name} = \@pi_outputs;
        
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
            fedby_modules => [],
            fedby_modules_inst => [],
            fwd_modules => [],
            fwd_modules_inst => [],
            processed => 'not_key',
            count => $ml_count,
        });
        
        $the_circuit{$po_node_name} = $po_obj;
        push @list_of_modules, $po_node_name;
        
        push @tr, $ml_count if $trial == 3;
        push @va, $ml_count if $trial == 1;
        push @te, $ml_count if $trial == 2;
        $ml_count++;
    }

    # SECOND PASS: create gate objects
    open $IN, '<', "$input_file_path/$input_file" or die "Can't reopen $input_file: $!";

    while (<$IN>) {
        my $line = $_;
        next if $line =~ /^\s*\/\//;

        # RTL ternary assignment: create an explicit MUX graph node.
        # Example: wire [31:0] op1_sel = key[0] ? op1_p1 : op1_p0;
        if ( $line =~ /^\s*(?:wire|reg|logic)\s+(?:\[[^\]]+\]\s+)?(\w+)\s*=\s*([^?;]+?)\s*\?\s*([^:;]+?)\s*:\s*([^;]+?)\s*;/ ) {
            my ($out, $sel, $when_one, $when_zero) = map { trim($_) } ($1, $2, $3, $4);
            my $modname = "ternary_mux_$assign_count";
            my @ins = ($when_zero, $when_one, $sel);
            my @outs = ($out);
            my %pm = ( a => $when_zero, b => $when_one, s => $sel );

            my $obj = theCircuit->new({
                name => $modname,
                inputs => \@ins,
                outputs => \@outs,
                bool_func => 'MUX',
                fedby_modules => [],
                fedby_modules_inst => [],
                fwd_modules => [undef],
                fwd_modules_inst => [undef],
                processed => 'not_key',
                count => $ml_count,
                port_map => \%pm,
            });
            $the_circuit{$modname} = $obj;
            push @list_of_modules, $modname;
            $module_to_outputs{$modname} = \@outs;
            $wire_to_module_output{$out} = $modname;

            push @tr, $ml_count if $trial == 3;
            push @va, $ml_count if $trial == 1;
            push @te, $ml_count if $trial == 2;
            $ml_count++; $assign_count++;
            next;
        }

        # Simple assign statements
        if ( $line =~ /^\s*assign\s+(\S+)\s*=\s*(\S+)\s*;/ ) {
            my ($out,$in) = ($1,$2);
            $out =~ s/\[.*?\]//g; 
            $in =~ s/\[.*?\]//g;
            my $modname = "assign_$assign_count";
            push @list_of_modules, $modname;
            my @ins = ($in);
            my @outs = ($out);
            my @fedby_t = ();
            my @fedby_n = ();

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

            my $obj = theCircuit->new({
                name => $modname,
                inputs => \@ins,
                outputs => \@outs,
                bool_func => 'LOGIC',
                fedby_modules => \@fedby_t,
                fedby_modules_inst => \@fedby_n,
                fwd_modules => [undef],
                fwd_modules_inst => [undef],
                processed => $processed,
                count => $ml_count,
            });
            $the_circuit{$modname} = $obj;
            $module_to_outputs{$modname} = \@outs;

            push @tr, $ml_count if $trial == 3;
            push @va, $ml_count if $trial == 1;
            push @te, $ml_count if $trial == 2;
            $ml_count++; $assign_count++;
            next;
        }

        # handle multi-line instances
        if ( $line =~ /^\s*(?!module\b|function\b|task\b)\w+\s+\w+\s*\(/
             && $line !~ /\)\s*;/ ) {
            my $multi = $line;
            while (<$IN>) {
                $multi .= $_;
                last if $_ =~ /\)\s*;/;
            }
            $line = $multi;
        }

        # gate/module instance
        if ( $line =~ /^\s*(\S+)\s+(\S+)\s*\((.+?)\)\s*;/s ) {
            my ($cell,$inst,$ports_str) = ($1,$2,$3);
            next if $cell eq 'module' || $cell eq 'endmodule' || $cell eq 'primitive' || $cell eq 'initial';
            my @pairs = split /\s*,\s*/, $ports_str;
            my %local = ();
            foreach my $p (@pairs) {
                if ($p =~ /\.(\w+)\s*\(\s*(\S+)\s*\)/) { $local{$1} = $2; }
            }

            my @current_ins = ();
            my @current_outs = ();

            # Determine if this is a DEMUX module (its 'a' and 'b' ports are outputs)
            my $is_demux = ($cell =~ /demux/i) ? 1 : 0;

            # Comprehensive RTL input port names
            # Note: 'a' and 'b' are excluded here for DEMUX (handled separately below)
            foreach my $p (qw(
                c d e f g h i j k l m n o p q r s t u v w x y z
                data data0 data1 data2 data3 in in0 in1 in2 in3 sel select select0 select1
                en enable clk clock rst reset din datain s
                a_operand b_operand AddBar_Sub reg_in
                A B C D E F G H I J K L M N O P Q R S T U V W X Y Z
                A0 A1 A2 A3 B0 B1 B2 B3 C0 C1 CI CIN CLK D0 D1
            )) {
                if ( defined $local{$p} ) {
                    push @current_ins, $local{$p};
                }
            }
            # 'a' and 'b': INPUT for MUX/Multiplier, OUTPUT for DEMUX
            if ( !$is_demux ) {
                for my $p (qw(a b)) {
                    push @current_ins, $local{$p} if defined $local{$p};
                }
            }

            # RTL output port names
            foreach my $p (qw(result out output sum product diff quotient res Y Z Q QN ZN S CO COUT z zout q qq dout dataout reg_out)) {
                if ( defined $local{$p} ) {
                    push @current_outs, $local{$p};
                }
            }
            # DEMUX-specific: 'a' and 'b' are the demuxed outputs
            if ( $is_demux ) {
                for my $p (qw(a b)) {
                    push @current_outs, $local{$p} if defined $local{$p};
                }
            }


            # Normalize bool func with RTL operators
            my $bool_fun = uc($cell);
            $bool_fun =~ s/\d+\D*$//g; # strip bitwidth like 32bit

            # RTL operator normalization - match actual module names from Verilog
            if    ($bool_fun =~ /^(MUX|SEL|SELECT)/)           { $bool_fun = 'MUX'; }
            elsif ($bool_fun =~ /^(DEMUX|DESEL)/)              { $bool_fun = 'DEMUX'; }
            elsif ($bool_fun =~ /^(ADD|ADDER|FP[_]?ADD|ADD_SUB)/) { $bool_fun = 'ADD'; }
            elsif ($bool_fun =~ /^(MUL|MULT|MULTIPLIER|FP[_]?MUL)/) { $bool_fun = 'MUL'; }
            elsif ($bool_fun =~ /^(SUB|SUBTRACT|FP[_]?SUB)/)   { $bool_fun = 'SUB'; }
            elsif ($bool_fun =~ /^(REG|REGISTER|DFF|DFFR)/)    { $bool_fun = 'REG'; }
            elsif ($bool_fun =~ /^(LATCH|LAT)/)                { $bool_fun = 'LATCH'; }
            else                                               { $bool_fun = 'MUX'; } # default to MUX

            my $processed = 'not_key';

            my %port_id_map = ();
            foreach my $pk ( keys %local ) {
                my $pw = $local{$pk};
                $pw =~ s/\[.*?\]//g;
                $port_id_map{ lc($pk) } = $pw;
            }

            my $obj = theCircuit->new({
                name => $inst,
                inputs => \@current_ins,
                outputs => \@current_outs,
                bool_func => $bool_fun,
                fedby_modules => [],
                fedby_modules_inst => [],
                fwd_modules => [undef],
                fwd_modules_inst => [undef],
                processed => $processed,
                count => $ml_count,
                port_map => \%port_id_map,
            });

            $the_circuit{$inst} = $obj;
            push @list_of_modules, $inst;
            $module_to_outputs{$inst} = \@current_outs;

            foreach my $outw_raw (@current_outs) {
                my $outw = $outw_raw; $outw =~ s/\[.*?\]//g;
                $wire_to_module_output{$outw} = $inst;
            }

            push @tr, $ml_count if $trial == 3;
            push @va, $ml_count if $trial == 1;
            push @te, $ml_count if $trial == 2;
            $ml_count++;
            next;
        }
    }
    close $IN;

    # THIRD PASS: Build connectivity
    foreach my $inst ( @list_of_modules ) {
        next unless exists $the_circuit{$inst};
        my $obj = $the_circuit{$inst};
        my @inputs = $obj->get_inputs();
        my @fedby_types = ();
        my @fedby_inst  = ();
        foreach my $inw_raw (@inputs) {
            my $inw = $inw_raw; $inw =~ s/\[.*?\]//g;
            my $normalized = $inw;
            if ( exists $wire_to_module_output{$inw} ) {
                my $src_inst = $wire_to_module_output{$inw};
                push @fedby_types, $the_circuit{$src_inst}->get_bool_func() || 'UNKNOWN';
                push @fedby_inst, $src_inst;
                my @fwd = $the_circuit{$src_inst}->get_fwd_modules();
                my @fwd_inst = $the_circuit{$src_inst}->get_fwd_modules_inst();
                push @fwd, uc($obj->get_bool_func());
                push @fwd_inst, $inst;
                $the_circuit{$src_inst}->set_fwd_modules(\@fwd);
                $the_circuit{$src_inst}->set_fwd_modules_inst(\@fwd_inst);
            } else {
                if ( exists $Netlist_Inputs_Hash{$inw} || exists $Netlist_Inputs_Hash{$normalized} ) {
                    push @fedby_types, "PI";
                    push @fedby_inst, $inw;
                } else {
                    push @fedby_types, "NET";
                    push @fedby_inst, $inw;
                }
            }
        }
        $obj->set_fedby_modules(\@fedby_types);
        $obj->set_fedby_modules_inst(\@fedby_inst);
        $the_circuit{$inst} = $obj;
    }

    # Resolve NETs
    foreach my $inst ( @list_of_modules ) {
        next unless exists $the_circuit{$inst};
        my $obj = $the_circuit{$inst};
        my @fedby_inst = $obj->get_fedby_modules_inst();
        my @fedby_types = $obj->get_fedby_modules();
        for my $i (0..$#fedby_inst) {
            my $entry = $fedby_inst[$i];
            if (defined $entry && $entry ne 'NET') {
                next;
            }
            my $candidate = $fedby_inst[$i];
            foreach my $g ( @list_of_modules ) {
                next unless exists $the_circuit{$g};
                my @gouts = $the_circuit{$g}->get_outputs();
                foreach my $o (@gouts) {
                    if (!defined $candidate) { next; }
                    (my $c_norm = $candidate) =~ s/\[.*?\]//g;
                    (my $o_norm = $o) =~ s/\[.*?\]//g;
                    if ( $c_norm eq $o_norm ) {
                        $fedby_inst[$i] = $g;
                        $fedby_types[$i] = $the_circuit{$g}->get_bool_func();
                        my @fwd = $the_circuit{$g}->get_fwd_modules();
                        my @fwd_inst = $the_circuit{$g}->get_fwd_modules_inst();
                        push @fwd, $obj->get_bool_func();
                        push @fwd_inst, $inst;
                        $the_circuit{$g}->set_fwd_modules(\@fwd);
                        $the_circuit{$g}->set_fwd_modules_inst(\@fwd_inst);
                        last;
                    }
                }
            }
        }
        $obj->set_fedby_modules_inst(\@fedby_inst);
        $obj->set_fedby_modules(\@fedby_types);
        $the_circuit{$inst} = $obj;
    }

    # Connect PO nodes
    foreach my $inst ( @list_of_modules ) {
        next unless exists $the_circuit{$inst};
        my $obj = $the_circuit{$inst};
        next unless $obj->get_bool_func() eq 'PO';
        
        my @po_inputs = $obj->get_inputs();
        my @fedby_types = ();
        my @fedby_inst = ();
        
        foreach my $po_in_raw (@po_inputs) {
            my $po_in = $po_in_raw; $po_in =~ s/\[.*?\]//g;
            if ( exists $wire_to_module_output{$po_in} ) {
                my $src_inst = $wire_to_module_output{$po_in};
                next if $src_inst eq $inst;
                
                    if ( exists $the_circuit{$src_inst} ) {
                        push @fedby_types, $the_circuit{$src_inst}->get_bool_func();
                        push @fedby_inst, $src_inst;
                        
                        my @fwd = $the_circuit{$src_inst}->get_fwd_modules();
                        my @fwd_inst = $the_circuit{$src_inst}->get_fwd_modules_inst();
                        push @fwd, 'PO';
                        push @fwd_inst, $inst;
                        $the_circuit{$src_inst}->set_fwd_modules(\@fwd);
                        $the_circuit{$src_inst}->set_fwd_modules_inst(\@fwd_inst);
                    }
                } else {
                    (my $po_in_norm = $po_in) =~ s/\[.*?\]//g;
                    foreach my $g ( @list_of_modules ) {
                        next unless exists $the_circuit{$g};
                        next if $the_circuit{$g}->get_bool_func() eq 'PO';
                        my @gouts = $the_circuit{$g}->get_outputs();
                        foreach my $o (@gouts) {
                            (my $o_norm = $o) =~ s/\[.*?\]//g;
                            if ( $o_norm eq $po_in_norm ) {
                                push @fedby_types, $the_circuit{$g}->get_bool_func();
                                push @fedby_inst, $g;
                                
                                my @fwd = $the_circuit{$g}->get_fwd_modules();
                                my @fwd_inst = $the_circuit{$g}->get_fwd_modules_inst();
                                push @fwd, 'PO';
                                push @fwd_inst, $inst;
                                $the_circuit{$g}->set_fwd_modules(\@fwd);
                                $the_circuit{$g}->set_fwd_modules_inst(\@fwd_inst);
                                last;
                            }
                        }
                    }
                }
            }
        
        $obj->set_fedby_modules(\@fedby_types);
        $obj->set_fedby_modules_inst(\@fedby_inst);
        $the_circuit{$inst} = $obj;
    }

    # Detect key components (DISABLED for KPA focus)
    # my @key_modules = ();
    # foreach my $inst ( @list_of_modules ) {
    #     ...
    # }
    my @key_modules = grep { $the_circuit{$_}->get_bool_func() eq 'PI' && $the_circuit{$_}->get_processed() =~ /key/ } @list_of_modules;

    # BFS from key datapaths
    my $dist_ref = {};
    if (@key_modules) {
        $dist_ref = bfs_from_roots(\@key_modules, \%the_circuit);
        print $FH_DEBUG "BFS DISTANCES summary:\n";
        my %count_by_dist = ();
        foreach my $k (keys %{$dist_ref}) {
            my $d = $dist_ref->{$k};
            $count_by_dist{$d}++;
        }
        foreach my $d (sort { $a <=> $b } keys %count_by_dist) {
            print $FH_DEBUG "  dist $d : $count_by_dist{$d} nodes\n";
        }
    } else {
        print $FH_DEBUG "No key-components detected in file $input_file\n";
    }

    # Build instance->count mapping
    my %inst_to_count = ();
    foreach my $inst ( @list_of_modules ) {
        next unless exists $the_circuit{$inst};
        $inst_to_count{$inst} = $the_circuit{$inst}->get_count();
    }

    # Keyed MUX/DEMUX: flatten to candidate links; mark obfuscated units + influenced inputs
    # Port a (1st input): KEY=0, OBF_UNIT=1 | Port b (2nd input): KEY=1, OBF_UNIT=1
    my %flatten_mux_insts = ();
    my %obf_key0_counts = ();    # first input port: KEY=0, OBF_UNIT=1
    my %obf_key1_counts = ();    # second input port: KEY=1, OBF_UNIT=1
    my %obf_active_key = ();     # which key is active on this obfuscated unit: 0=key0, 1=key1
    my %keyid_canonical_mux = (); # KeyinputN -> one MUX/DEMUX node count (real obfuscation only)

    foreach my $inst ( @list_of_modules ) {
        next unless exists $the_circuit{$inst};
        my $obj = $the_circuit{$inst};
        my $module_type = uc( $obj->get_bool_func() || '' );
        next unless $module_type =~ /^(MUX|DEMUX)$/;

        my %pm = $obj->get_port_map();
        my $sel_wire = $pm{s} || $pm{sel} || $pm{select};
        next unless defined $sel_wire && is_likely_key($sel_wire);

        $flatten_mux_insts{$inst} = 1;
        my $key_bit = mux_select_key_bit( $sel_wire, $file_key_string );
        $obj->set_processed( get_key_label_by_key_bit($key_bit) );
        if ( !defined $key_bit ) {
            print $FH_DEBUG "WARNING: no ground-truth key bit for select $sel_wire on $inst; node will not be labelled\n";
            next;
        }

        my $kid = key_id_from_select_wire($sel_wire);
        if ( defined $kid && $kid >= 1 && !exists $keyid_canonical_mux{$kid} ) {
            $keyid_canonical_mux{$kid} = $obj->get_count();
        }

        my $mux_count = $obj->get_count();
        if ( $key_bit == 0 ) { $obf_key0_counts{$mux_count} = 1; }
        else                   { $obf_key1_counts{$mux_count} = 1; }
        $obf_active_key{$mux_count} = $key_bit;

        if ( $module_type eq 'MUX' ) {
            foreach my $port (qw(a in0)) {
                next unless defined $pm{$port};
                my $sc = resolve_src_count_for_wire(
                    $pm{$port}, \%wire_to_module_output, \%the_circuit, \@list_of_modules
                );
                if ( defined $sc ) {
                    $obf_key0_counts{$sc} = 1;
                    $obf_active_key{$sc} = $key_bit;
                }
            }
            foreach my $port (qw(b in1)) {
                next unless defined $pm{$port};
                my $sc = resolve_src_count_for_wire(
                    $pm{$port}, \%wire_to_module_output, \%the_circuit, \@list_of_modules
                );
                if ( defined $sc ) {
                    $obf_key1_counts{$sc} = 1;
                    $obf_active_key{$sc} = $key_bit;
                }
            }
        }
        elsif ( $module_type eq 'DEMUX' ) {
            my $in_wire = $pm{in} || $pm{data} || $pm{din} || $pm{datain};
            if ( defined $in_wire ) {
                my $sc = resolve_src_count_for_wire(
                    $in_wire, \%wire_to_module_output, \%the_circuit, \@list_of_modules
                );
                if ( defined $sc ) {
                    if ( $key_bit == 0 ) { $obf_key0_counts{$sc} = 1; }
                    else                 { $obf_key1_counts{$sc} = 1; }
                    $obf_active_key{$sc} = $key_bit;
                }
            }
            foreach my $port (qw(a out0)) {
                next unless defined $pm{$port};
                foreach my $dc ( consumers_of_wire( $pm{$port}, \@list_of_modules, \%the_circuit ) ) {
                    $obf_key0_counts{$dc} = 1;
                    $obf_active_key{$dc} = $key_bit;
                }
            }
            foreach my $port (qw(b out1)) {
                next unless defined $pm{$port};
                foreach my $dc ( consumers_of_wire( $pm{$port}, \@list_of_modules, \%the_circuit ) ) {
                    $obf_key1_counts{$dc} = 1;
                    $obf_active_key{$dc} = $key_bit;
                }
            }
        }
    }

    # Output generation
    my %is_tr = map { $_ => 1 } @tr;
    my %is_va = map { $_ => 1 } @va;
    my %is_te = map { $_ => 1 } @te;

    foreach my $inst ( @list_of_modules ) {
        next unless exists $the_circuit{$inst};
        my $obj = $the_circuit{$inst};
        my $count = $obj->get_count();
        my $name = $obj->get_name();
        my $module_type = uc($obj->get_bool_func() || 'LOGIC');

        # Leakage-free 7-bit RTL vector:
        # [PI, PO, KEY_PI, MUX, ADD, SUB, MUL]
        my @features_array = (0) x 7;

        # Keep the MUX feature on keyed/flattened MUX nodes.  The correct
        # key bit is deliberately absent from feat.txt and exists only as a label.
        if ( exists $features_map{$module_type}
             && $module_type ne 'PI' && $module_type ne 'PO' ) {
            $features_array[ $features_map{$module_type} ] = 1;
        }

        $features_array[ $features_map{"PI"} ] = 1 if $module_type eq 'PI';
        $features_array[ $features_map{"PO"} ] = 1 if $module_type eq 'PO';

        # KEY_PI is set only on an actual primary key-input port.
        if ( $module_type eq 'PI' ) {
            foreach my $out ( $obj->get_outputs() ) {
                my $ow = normalize_wire($out);
                if ( is_likely_key($ow) ) {
                    $features_array[ $features_map{"KEY_PI"} ] = 1;
                    last;
                }
            }
        }

        print $FH_FEAT join(' ', @features_array) . "\n";

        # KPA labels: Group B only (keyed MUX/DEMUX), one graph node per KeyinputN.
        # Group A (PI_Keyinput*) is a port declaration — not a separate key prediction.
        my $processed = $obj->get_processed();
        my $label = 2;
        if ( defined $processed ) {
            if ( $processed =~ /key0/i ) { $label = 0; }
            elsif ( $processed =~ /key1/i ) { $label = 1; }
        }

        my $emit_kpa_label = 0;
        if ( $label <= 1 && exists $flatten_mux_insts{$inst} ) {
            my %pm_kpa = $obj->get_port_map();
            my $sel_kpa = $pm_kpa{s} || $pm_kpa{sel} || $pm_kpa{select};
            if ( defined $sel_kpa ) {
                my $kid = key_id_from_select_wire($sel_kpa);
                if ( defined $kid && exists $keyid_canonical_mux{$kid}
                     && $keyid_canonical_mux{$kid} == $count ) {
                    $emit_kpa_label = 1;
                }
            }
        }

        if ( $emit_kpa_label ) {
            if ( exists $is_tr{$count} ) {
                print $FH_NODE_TR_POS "$count\n" if $label == 0;
                print $FH_NODE_TR_NEG "$count\n" if $label == 1;
            } elsif ( exists $is_va{$count} ) {
                print $FH_NODE_VA_POS "$count\n" if $label == 0;
                print $FH_NODE_VA_NEG "$count\n" if $label == 1;
            } elsif ( exists $is_te{$count} ) {
                print $FH_NODE_TE_POS "$count\n" if $label == 0;
                print $FH_NODE_TE_NEG "$count\n" if $label == 1;
            }
        }

        print $FH_CELL "$count $name from file $input_file\n";
        print $FH_COUNT "$count\n";
    }

    # Write links (skip routing through flattened keyed MUX/DEMUX; add candidate links)
    my %seen_links = ();

    foreach my $inst ( @list_of_modules ) {
        next unless exists $the_circuit{$inst};
        my $obj = $the_circuit{$inst};
        my $src_count = $obj->get_count();
        my @fwd_inst = $obj->get_fwd_modules_inst();

        foreach my $dst (@fwd_inst) {
            next unless defined $dst;
            next if $dst eq 'undef' || $dst eq 'PO';
            next if exists $flatten_mux_insts{$inst} || exists $flatten_mux_insts{$dst};
            if ( exists $the_circuit{$dst} ) {
                my $dst_count = $the_circuit{$dst}->get_count();
                next if $src_count == $dst_count;
                my $lk = "$src_count $dst_count";
                unless ( exists $seen_links{$lk} ) {
                    $seen_links{$lk} = 1;
                    print $FH_LINK "$src_count $dst_count\n";
                }
            }
        }
    }

    # MUX/DEMUX -> possible directed links (link prediction candidates)
    foreach my $inst ( keys %flatten_mux_insts ) {
        next unless exists $the_circuit{$inst};
        my $obj = $the_circuit{$inst};
        my %pm = $obj->get_port_map();
        my $module_type = uc( $obj->get_bool_func() || '' );

        if ( $module_type eq 'MUX' ) {
            my @out_wires = $obj->get_outputs();
            my @dst_counts = ();
            foreach my $ow (@out_wires) {
                push @dst_counts, consumers_of_wire( $ow, \@list_of_modules, \%the_circuit );
            }
            my %uniq_dst = map { $_ => 1 } @dst_counts;
            @dst_counts = keys %uniq_dst;

            foreach my $port (qw(a b in0 in1)) {
                next unless defined $pm{$port};
                my $src_count = resolve_src_count_for_wire(
                    $pm{$port}, \%wire_to_module_output, \%the_circuit, \@list_of_modules
                );
                next unless defined $src_count;
                foreach my $dc (@dst_counts) {
                    next if $src_count == $dc;
                    my $lk = "$src_count $dc";
                    unless ( exists $seen_links{$lk} ) {
                        $seen_links{$lk} = 1;
                        print $FH_LINK "$src_count $dc\n";
                    }
                }
            }
        }
        elsif ( $module_type eq 'DEMUX' ) {
            my $in_wire = $pm{in} || $pm{data} || $pm{din} || $pm{datain};
            next unless defined $in_wire;
            my $src_count = resolve_src_count_for_wire(
                $in_wire, \%wire_to_module_output, \%the_circuit, \@list_of_modules
            );
            next unless defined $src_count;
            foreach my $port (qw(a b out0 out1)) {
                next unless defined $pm{$port};
                foreach my $dc ( consumers_of_wire( $pm{$port}, \@list_of_modules, \%the_circuit ) ) {
                    next if $src_count == $dc;
                    my $lk = "$src_count $dc";
                    unless ( exists $seen_links{$lk} ) {
                        $seen_links{$lk} = 1;
                        print $FH_LINK "$src_count $dc\n";
                    }
                }
            }
        }
    }

    print $FH_DEBUG "Completed $input_file: modules=" . scalar(keys %the_circuit) . " key_modules=" . scalar(@key_modules) . "\n\n";

    # Update global counter for next file - DO NOT reset to 0!
    $ml_global_count = $ml_count;

    @list_of_modules = ();
    %the_circuit = ();
    %module_to_outputs = ();
    %wire_to_module_output = ();
    %keyinput_map = ();
    # NOTE: @tr, @va, @te are NOT reset here - they accumulate across all files!
}

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
print STDERR "RTL netlist processing completed in $run_time sec\n";
print STDERR "Feature vector length: 7 (PI, PO, KEY_PI, MUX, ADD, SUB, MUL)\n";
print STDERR "Correct key values are labels only; feat.txt contains no key-value feature.\n";
print STDERR "KPA labels: keyed MUX/DEMUX only (1 node per KeyinputN); PI_Keyinput excluded\n";
exit 0;
