package PVE::LXC::Config;

use strict;
use warnings;

use PVE::Utils qw(get_numa_topology parse_cpu_list get_thread_siblings);

my %OPTION_DEFAULTS = (
    numa_optimized  => 0,
    numa_nodes      => [],
    numa_grouping   => 'auto',
    numa_bind_memory => 0,
);

sub validate_numa_options {
    my ($conf) = @_;

    $conf->{numa_optimized} //= $OPTION_DEFAULTS{numa_optimized};
    $conf->{numa_grouping}  //= $OPTION_DEFAULTS{numa_grouping};
    $conf->{numa_bind_memory} //= $OPTION_DEFAULTS{numa_bind_memory};
    $conf->{numa_nodes} //= $OPTION_DEFAULTS{numa_nodes};

    if ($conf->{numa_optimized}) {
        die "numa_nodes must be an array reference" if ref($conf->{numa_nodes}) ne 'ARRAY';
        die "numa_nodes cannot be empty when numa_optimized is enabled" if !@{ $conf->{numa_nodes} };
    }

    if (defined $conf->{numa_grouping}) {
        die "invalid numa_grouping" if $conf->{numa_grouping} !~ /^(contiguous|smt|auto)$/;
    }
}

# Select CPUs from requested NUMA nodes with the given mode.
sub select_numa_cpus {
    my ($topology, $requested_nodes, $count, $mode) = @_;
    die "count must be positive" if !$count || $count < 1;
    die "no NUMA nodes provided" if !@$requested_nodes;

    my @selected;
    $mode ||= 'auto';

    for my $node (@$requested_nodes) {
        my $cpus = $topology->{$node} // [];
        next if !@$cpus;

        if ($mode eq 'smt') {
            my %added;
            for my $cpu (@$cpus) {
                next if $added{$cpu};
                my $siblings = get_thread_siblings($cpu);
                if (@$siblings) {
                    for my $sib (@$siblings) {
                        push @selected, $sib unless $added{$sib};
                        $added{$sib} = 1;
                    }
                } else {
                    push @selected, $cpu;
                    $added{$cpu} = 1;
                }
                last if @selected >= $count;
            }
        } else { # contiguous or auto
            push @selected, @$cpus;
        }

        last if @selected >= $count;
    }

    splice(@selected, $count) if @selected > $count;
    return \@selected;
}

# Build cpuset and mems entries if NUMA optimization is enabled and viable.
sub apply_numa_cpuset {
    my ($conf) = @_;
    validate_numa_options($conf);

    return {} if !$conf->{numa_optimized};

    my $topology = get_numa_topology();
    return {} if !%$topology;

    my @nodes = @{ $conf->{numa_nodes} // [] };
    return {} if !@nodes;

    my $count = $conf->{cores} || scalar @nodes; # fall back to node count if cores is absent
    my $mode  = $conf->{numa_grouping} || 'auto';

    my $cpus = select_numa_cpus($topology, \@nodes, $count, $mode);
    return {} if !@$cpus;

    my $cpu_list  = join(',', @$cpus);
    my $node_list = join(',', @nodes);

    my %out = (
        'lxc.cgroup2.cpuset.cpus' => $cpu_list,
    );

    if ($conf->{numa_bind_memory}) {
        $out{'lxc.cgroup2.cpuset.mems'} = $node_list;
    }

    return \%out;
}

# A simplified stand-in for write_config that focuses on NUMA cpuset emission.
sub write_config {
    my ($vmid, $conf, $fh) = @_;
    my $entries = apply_numa_cpuset($conf);

    return if !$entries || !%$entries;

    my $handle = $fh // *STDOUT;
    print {$handle} "# NUMA-aware cpuset for $vmid\n";
    for my $key (sort keys %$entries) {
        print {$handle} "$key = $entries->{$key}\n";
    }
}

1;

__END__

=head1 NAME

PVE::LXC::Config - NUMA-aware cpuset helpers inspired by Proxmox VE.

=head1 DESCRIPTION

Provides minimal versions of configuration validation and cpuset generation
sufficient to illustrate how the NUMA-aware CPU assignment plan can be wired into
`write_config` in a full Proxmox VE tree.

=cut
