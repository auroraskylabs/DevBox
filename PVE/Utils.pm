package PVE::Utils;

use strict;
use warnings;
use POSIX qw(strftime);
use Exporter 'import';

our @EXPORT_OK = qw(get_numa_topology parse_cpu_list get_thread_siblings);

# Parse CPU list strings such as "0-3,8,10-12" into a sorted list of integers.
sub parse_cpu_list {
    my ($cpulist) = @_;
    return [] if !defined($cpulist) || $cpulist eq '';

    my %seen;
    for my $chunk (split(/,/, $cpulist)) {
        if ($chunk =~ /^(\d+)-(\d+)$/) {
            my ($start, $end) = ($1, $2);
            ($start, $end) = ($end, $start) if $start > $end;
            $seen{$_} = 1 for ($start .. $end);
        } elsif ($chunk =~ /^(\d+)$/) {
            $seen{$1} = 1;
        }
    }

    return [sort { $a <=> $b } keys %seen];
}

# Return a hashref mapping NUMA node id to an arrayref of CPU ids.
# The function reads from sysfs and is tolerant to missing files so it can be
# exercised in minimal environments.
sub get_numa_topology {
    my $sysfs = '/sys/devices/system/node';
    my %nodes;

    opendir(my $dh, $sysfs) or return {};
    while (my $entry = readdir($dh)) {
        next if $entry !~ /^node(\d+)$/;
        my $node = $1;
        my $cpulist_path = "$sysfs/$entry/cpulist";
        next if !-f $cpulist_path;
        if (open(my $fh, '<', $cpulist_path)) {
            my $line = <$fh>;
            close($fh);
            chomp($line) if defined $line;
            my $cpus = parse_cpu_list($line);
            $nodes{$node} = $cpus if @$cpus;
        }
    }
    closedir($dh);

    return \%nodes;
}

# Returns an arrayref of SMT siblings for a CPU if sysfs provides it.
sub get_thread_siblings {
    my ($cpu) = @_;
    my $path = "/sys/devices/system/cpu/cpu$cpu/topology/thread_siblings_list";
    return [] if !-f $path;

    if (open(my $fh, '<', $path)) {
        my $line = <$fh>;
        close($fh);
        chomp($line) if defined $line;
        return parse_cpu_list($line);
    }

    return [];
}

1;

__END__

=head1 NAME

PVE::Utils - Minimal NUMA helper utilities for Proxmox-style environments.

=head1 DESCRIPTION

Provides helpers to parse CPU lists, discover host NUMA topology, and fetch SMT
thread siblings from sysfs. The module is intentionally lightweight so it can
run in reduced environments used by this repository.

=cut
