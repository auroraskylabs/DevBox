# NUMA-Aware CPU Assignment for LXC on Proxmox VE 9

This repository snapshot does not include the Proxmox VE source tree, so the implementation
cannot be applied directly here. The following document captures actionable notes and code
sketches derived from the provided implementation plan, aligned with the upstream file
structure. The intent is to help port the feature into a working PVE 9 checkout.

## Key touchpoints in the PVE tree
- `PVE/LXC/Config.pm` — configuration parsing/serialization and cpuset emission.
- `PVE/Utils.pm` (or a new helper) — host NUMA discovery helpers.
- `PVE/API2/LXC.pm` — API validation and schema extensions for the new options.
- `www/manager6/lxc/Resources.js` — optional UI controls for enabling NUMA-aware CPU
  assignment.

## Proposed configuration schema additions
Add the following optional keys to the LXC config schema (defaulting to legacy behavior when
unset):

```
numa_optimized: boolean
numa_nodes: array of NUMA node IDs
numa_grouping: enum(contiguous|smt|auto)
numa_bind_memory: boolean
```

### Parsing/storage hints
- Mirror existing option handling patterns in `PVE::LXC::Config` and `PVE::API2::LXC`.
- When absent, avoid emitting any cpuset changes to preserve backward compatibility.

## NUMA detection helper (Perl sketch)
```perl
# in PVE/Utils.pm or a dedicated helper
sub get_numa_topology {
    my $sysfs = '/sys/devices/system/node';
    my %nodes;

    for my $entry (PVE::Tools::dir_glob_regex($sysfs, 'node(\\d+)')) {
        if ($entry =~ /node(\d+)/) {
            my $node = $1;
            my $cpulist = PVE::Tools::file_read_firstline("$sysfs/$entry/cpulist");
            next if !defined($cpulist);
            my $cpus = PVE::CpuSet->new_from_cpulist($cpulist)->members; # iterator to list
            $nodes{$node} = [@$cpus];
        }
    }

    return \%nodes; # { nodeid => [cpu ids...] }
}
```

## NUMA-aware CPU selection (Perl sketch)
```perl
sub select_numa_cpus {
    my ($topology, $requested_nodes, $count, $mode) = @_;

    my @nodes = @$requested_nodes;
    die "count must be positive" if !$count;
    die "no NUMA nodes provided" if !@nodes;

    my @selected;
    my $mode = $mode // 'auto';

    for my $node (@nodes) {
        my $cpus = $topology->{$node} // [];
        next if !@$cpus;

        if ($mode eq 'smt') {
            # pair sibling threads first (simple adjacent pairing fallback)
            push @selected, @$cpus;
        } else { # contiguous/auto
            push @selected, @$cpus;
        }
        last if @selected >= $count;
    }

    splice(@selected, $count) if @selected > $count;
    return \@selected;
}
```
- A production-quality SMT mode should group logical siblings (e.g., via
  `/sys/devices/system/cpu/cpu*/topology/thread_siblings_list`).
- The `auto` mode can initially alias to `contiguous`.

## cpuset and mems emission (control flow notes)
1. During `write_config` in `PVE::LXC::Config`, guard all NUMA logic behind `numa_optimized`.
2. Resolve the host topology via the helper above.
3. Run `select_numa_cpus` with the requested nodes/count/mode.
4. If CPUs are returned, emit:
   - `lxc.cgroup2.cpuset.cpus = <comma list>`
   - `lxc.cgroup2.cpuset.mems = <node list>` when `numa_bind_memory` is set.
5. Preserve legacy behavior when any prerequisite is missing or invalid.

## API validation notes
- Extend the `create` and `update` schemas in `PVE::API2::LXC` to accept the new keys.
- Validate NUMA node IDs against the detected topology to avoid invalid cpuset generation.
- Ensure `numa_nodes` is optional but required when `numa_optimized` is true.

## UI considerations
- Under **Advanced CPU Settings** in `www/manager6/lxc/Resources.js`, add a fieldset that
toggles the new options. Use existing checkbox/radio patterns for consistency.
- Keep defaults aligned with legacy behavior (`numa_optimized` unchecked).

## Testing checklist
- Single-node host: verify generated cpuset/mems are either trivial (node 0) or omitted when
  disabled.
- Multi-socket host: confirm CPU lists stay within selected nodes and respect grouping mode.
- LXC startup: container should boot with generated cpuset.
- Memory binding: `cat /sys/fs/cgroup/lxc/<vmid>/cpuset.mems` reflects selected nodes when
  enabled.
- Backward compatibility: configs without the new keys should produce identical cpusets as
  before.
```
