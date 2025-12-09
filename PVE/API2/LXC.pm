package PVE::API2::LXC;

use strict;
use warnings;

use JSON::PP qw(encode_json);
use PVE::Utils qw(get_numa_topology);
use PVE::LXC::Config;

# Minimal schema representation capturing the new NUMA fields for demonstration.
our %COMMON_OPTIONS = (
    numa_optimized => {
        type => 'boolean',
        description => 'Enable NUMA-aware CPU selection for the container.',
        optional => 1,
    },
    numa_nodes => {
        type => 'array',
        format => 'integer-list',
        description => 'List of NUMA node IDs to pick CPUs from.',
        optional => 1,
    },
    numa_grouping => {
        type => 'string',
        enum => ['contiguous', 'smt', 'auto'],
        description => 'CPU selection strategy when multiple threads are available.',
        optional => 1,
    },
    numa_bind_memory => {
        type => 'boolean',
        description => 'Bind container memory allocation to the selected NUMA nodes.',
        optional => 1,
    },
);

sub validate_numa_request {
    my ($param) = @_;

    return if !$param->{numa_optimized};

    my $topology = get_numa_topology();
    die "no NUMA topology detected on host" if !%$topology;

    my $nodes = $param->{numa_nodes};
    die "numa_nodes must be provided when numa_optimized is set" if !$nodes;
    die "numa_nodes must be an array reference" if ref($nodes) ne 'ARRAY';

    my %valid = map { $_ => 1 } keys %$topology;
    for my $node (@$nodes) {
        die "invalid NUMA node $node" if !exists $valid{$node};
    }

    if (my $mode = $param->{numa_grouping}) {
        die "invalid numa_grouping" if $mode !~ /^(contiguous|smt|auto)$/;
    }
}

sub create {
    my ($param) = @_;
    validate_numa_request($param);
    # stub returning schema validation result for demonstration
    return encode_json({ status => 'validated', config => $param });
}

sub update {
    my ($param) = @_;
    validate_numa_request($param);
    return encode_json({ status => 'validated', config => $param });
}

1;

__END__

=head1 NAME

PVE::API2::LXC - Minimal API stubs exposing NUMA-aware options.

=head1 DESCRIPTION

Provides lightweight create/update stubs that validate the new NUMA fields against
host topology. In a full PVE tree, these would plug into the existing REST
framework and forward validated parameters to configuration writers.

=cut
