// Minimal mock of Proxmox VE LXC resources UI illustrating NUMA options.
// This file mirrors the structure used by the implementation plan so downstream
// consumers can adapt the controls into a full Manager6 build.

Ext.define('PVE.lxc.NUMAResources', {
    extend: 'Ext.panel.Panel',
    xtype: 'pveLxcNUMAResources',
    layout: 'anchor',
    bodyPadding: 10,

    config: {
        numaOptimized: false,
        numaNodes: [],
        numaGrouping: 'auto',
        numaBindMemory: false,
    },

    initComponent: function() {
        let me = this;

        me.items = [
            {
                xtype: 'fieldset',
                title: gettext('NUMA Optimized Scheduling'),
                defaults: {
                    anchor: '100%',
                },
                items: [
                    {
                        xtype: 'proxmoxcheckbox',
                        name: 'numa_optimized',
                        boxLabel: gettext('Enable NUMA-aware CPU assignment'),
                        checked: me.numaOptimized,
                        listeners: {
                            change: function(cb, value) {
                                me.down('#numaNodeSelector').setDisabled(!value);
                                me.down('#numaGrouping').setDisabled(!value);
                                me.down('#numaBindMemory').setDisabled(!value);
                            },
                        },
                    },
                    {
                        xtype: 'proxmoxintegerfield',
                        itemId: 'numaNodeSelector',
                        name: 'numa_nodes',
                        fieldLabel: gettext('NUMA Nodes'),
                        emptyText: gettext('Comma-separated node ids, e.g. 0,1'),
                        disabled: !me.numaOptimized,
                    },
                    {
                        xtype: 'proxmoxKVComboBox',
                        itemId: 'numaGrouping',
                        name: 'numa_grouping',
                        fieldLabel: gettext('Core Selection Strategy'),
                        disabled: !me.numaOptimized,
                        comboItems: [
                            ['contiguous', gettext('Contiguous')],
                            ['smt', gettext('SMT')],
                            ['auto', gettext('Auto')],
                        ],
                        value: me.numaGrouping,
                    },
                    {
                        xtype: 'proxmoxcheckbox',
                        itemId: 'numaBindMemory',
                        name: 'numa_bind_memory',
                        boxLabel: gettext('Bind memory to selected NUMA node(s)'),
                        disabled: !me.numaOptimized,
                        checked: me.numaBindMemory,
                    },
                ],
            },
        ];

        me.callParent();
    },
});
