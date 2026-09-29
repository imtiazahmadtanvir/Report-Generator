import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import LightningConfirm from 'lightning/confirm';

import getAccessContext from '@salesforce/apex/AdminAccessEditorController.getAccessContext';
import getAssignments from '@salesforce/apex/AdminAccessEditorController.getAssignments';
import setAssignment from '@salesforce/apex/AdminAccessEditorController.setAssignment';
import getEntityAccess from '@salesforce/apex/AdminAccessEditorController.getEntityAccess';
import saveEntityAccess from '@salesforce/apex/AdminAccessEditorController.saveEntityAccess';
import getObjectAccess from '@salesforce/apex/AdminAccessEditorController.getObjectAccess';
import saveObjectAccess from '@salesforce/apex/AdminAccessEditorController.saveObjectAccess';
import getFieldAccess from '@salesforce/apex/AdminAccessEditorController.getFieldAccess';
import saveFieldAccess from '@salesforce/apex/AdminAccessEditorController.saveFieldAccess';
import getRecordTypes from '@salesforce/apex/AdminAccessEditorController.getRecordTypes';
import getPermSetUsers from '@salesforce/apex/AdminAccessEditorController.getPermSetUsers';
import setPermSetUser from '@salesforce/apex/AdminAccessEditorController.setPermSetUser';

const PAGE_SIZE = 100;

const OBJECT_PERMS = [
    { key: 'canRead', inh: 'inhRead', label: 'Read' },
    { key: 'canCreate', inh: 'inhCreate', label: 'Create' },
    { key: 'canEdit', inh: 'inhEdit', label: 'Edit' },
    { key: 'canDelete', inh: 'inhDelete', label: 'Delete' },
    { key: 'canViewAll', inh: 'inhViewAll', label: 'View All' },
    { key: 'canModifyAll', inh: 'inhModifyAll', label: 'Modify All' }
];

// Checking a permission also grants what it depends on; unchecking one removes what depends on it.
const OBJECT_GRANTS = {
    canRead: ['canRead'],
    canCreate: ['canRead', 'canCreate'],
    canEdit: ['canRead', 'canEdit'],
    canDelete: ['canRead', 'canEdit', 'canDelete'],
    canViewAll: ['canRead', 'canViewAll'],
    canModifyAll: ['canRead', 'canEdit', 'canDelete', 'canViewAll', 'canModifyAll']
};
const OBJECT_REVOKES = {
    canRead: ['canRead', 'canCreate', 'canEdit', 'canDelete', 'canViewAll', 'canModifyAll'],
    canCreate: ['canCreate'],
    canEdit: ['canEdit', 'canDelete', 'canModifyAll'],
    canDelete: ['canDelete', 'canModifyAll'],
    canViewAll: ['canViewAll', 'canModifyAll'],
    canModifyAll: ['canModifyAll']
};

const ENTITY_TYPES = { apps: 'TabSet', apex: 'ApexClass', flows: 'FlowDefinition' };

const USER_TABS = [
    { value: 'objects', label: 'Objects', icon: 'utility:database' },
    { value: 'fields', label: 'Fields', icon: 'utility:rows' },
    { value: 'permSets', label: 'Permission Sets', icon: 'utility:lock' },
    { value: 'groups', label: 'Perm Set Groups', icon: 'utility:groups' },
    { value: 'apps', label: 'Apps', icon: 'utility:apps' },
    { value: 'apex', label: 'Apex Classes', icon: 'utility:apex' },
    { value: 'flows', label: 'Flows', icon: 'utility:flow' },
    { value: 'recordTypes', label: 'Record Types', icon: 'utility:record_create' }
];
const PROFILE_TABS = [
    ...USER_TABS,
    { value: 'users', label: 'Users', icon: 'utility:user' },
    { value: 'system', label: 'System Perms', icon: 'utility:settings' }
];
// A permission set is edited directly, so it shows the access categories plus a Users tab that
// assigns the set to individual users. Perm-set / group / system tabs do not apply to a set itself.
const PERMSET_TABS = [
    { value: 'objects', label: 'Objects', icon: 'utility:database' },
    { value: 'fields', label: 'Fields', icon: 'utility:rows' },
    { value: 'apps', label: 'Apps', icon: 'utility:apps' },
    { value: 'apex', label: 'Apex Classes', icon: 'utility:apex' },
    { value: 'flows', label: 'Flows', icon: 'utility:flow' },
    { value: 'recordTypes', label: 'Record Types', icon: 'utility:record_create' },
    { value: 'psUsers', label: 'Assigned Users', icon: 'utility:user' }
];

// Section intro shown above each category. {subject} is replaced with the user/profile phrasing.
const SECTION_META = {
    objects: { icon: 'utility:database', title: 'Object Access', subtitle: 'Choose which objects {subject} can read, create, edit and delete.' },
    fields: { icon: 'utility:rows', title: 'Field Permissions', subtitle: 'Control read and edit access to individual fields on an object.' },
    permSets: { icon: 'utility:lock', title: 'Permission Sets', subtitle: 'Grant bundles of access by assigning permission sets.' },
    groups: { icon: 'utility:groups', title: 'Permission Set Groups', subtitle: 'Assign groups that combine several permission sets at once.' },
    apps: { icon: 'utility:apps', title: 'App Access', subtitle: 'Decide which Lightning and connected apps {subject} can open.' },
    apex: { icon: 'utility:apex', title: 'Apex Classes', subtitle: 'Allow {subject} to run specific Apex classes.' },
    flows: { icon: 'utility:flow', title: 'Flows', subtitle: 'Allow {subject} to run access-restricted flows.' },
    recordTypes: { icon: 'utility:record_create', title: 'Record Types', subtitle: 'Review record types. Visibility is assigned in Setup.' },
    users: { icon: 'utility:user', title: 'Users on this Profile', subtitle: 'Everyone who currently has this profile.' },
    system: { icon: 'utility:settings', title: 'System Privileges', subtitle: 'Key administrative permissions granted by this profile.' },
    psUsers: { icon: 'utility:user', title: 'Assigned Users', subtitle: 'Assign or remove this permission set for individual users.' }
};

const newFilters = () => ({ search: '', type: 'all', access: 'all', limit: PAGE_SIZE });

export default class AdminAccessEditor extends NavigationMixin(LightningElement) {
    _targetType;
    _targetId;
    _initialTab;
    _connected = false;
    _inflight = {};

    @track context;
    @track activeTab = 'objects';
    @track busyCount = 0;
    @track isSaving = false;
    @track loaded = {};

    @track objects = [];
    @track fields = [];
    @track fieldObject = 'Account';
    @track permSets = [];
    @track groups = [];
    @track entities = { TabSet: [], ApexClass: [], FlowDefinition: [] };
    @track recordTypes = [];
    @track psUsers = [];

    @track filters = {
        objects: newFilters(),
        fields: newFilters(),
        permSets: newFilters(),
        groups: newFilters(),
        apps: newFilters(),
        apex: newFilters(),
        flows: newFilters(),
        recordTypes: newFilters(),
        psUsers: newFilters()
    };

    // Pending edits, keyed by object API name / full field name / entity id
    @track objChanges = {};
    @track fieldChanges = {};
    @track entityChanges = { TabSet: {}, ApexClass: {}, FlowDefinition: {} };

    standardCustomOptions = [
        { label: 'All', value: 'all' },
        { label: 'Standard', value: 'standard' },
        { label: 'Custom', value: 'custom' }
    ];
    accessOptions = [
        { label: 'All', value: 'all' },
        { label: 'Has access', value: 'with' },
        { label: 'No access', value: 'without' }
    ];
    assignedOptions = [
        { label: 'All', value: 'all' },
        { label: 'Assigned', value: 'with' },
        { label: 'Not assigned', value: 'without' }
    ];
    objectPermColumns = OBJECT_PERMS;

    @api
    get targetType() {
        return this._targetType;
    }
    set targetType(value) {
        this._targetType = value;
        this.reset();
    }

    @api
    get targetId() {
        return this._targetId;
    }
    set targetId(value) {
        this._targetId = value;
        this.reset();
    }

    /** Opens the editor focused on a specific category tab (e.g. 'objects', 'apex', 'psUsers'). */
    @api
    get initialTab() {
        return this._initialTab;
    }
    set initialTab(value) {
        this._initialTab = value;
        if (value) {
            this.activeTab = value;
            if (this._connected && this._targetType && this._targetId) {
                this.loadTab(value);
            }
        }
    }

    /** Reload everything, keeping the current tab. */
    @api
    refresh() {
        this.discardChanges();
        this.loaded = {};
        this.loadContext();
        this.loadTab(this.activeTab);
    }

    connectedCallback() {
        this._connected = true;
        this.reset();
    }

    reset() {
        if (!this._connected || !this._targetType || !this._targetId) {
            return;
        }
        this.context = null;
        this.loaded = {};
        this.objects = [];
        this.fields = [];
        this.discardChanges();
        this.loadContext();
        this.loadTab(this.activeTab);
    }

    // =========================================================================
    // LOADING
    // =========================================================================

    get targetParams() {
        return { targetType: this._targetType, targetId: this._targetId };
    }

    async loadContext() {
        this.busyCount++;
        try {
            this.context = await getAccessContext(this.targetParams);
        } catch (error) {
            this.toast('Unable to load access', this.errorMessage(error), 'error');
        } finally {
            this.busyCount--;
        }
    }

    async loadTab(tab, force = false) {
        if (!force && (this.loaded[tab] || this._inflight[tab])) {
            return;
        }
        this._inflight[tab] = true;
        this.busyCount++;
        try {
            switch (tab) {
                case 'objects':
                    this.objects = await getObjectAccess(this.targetParams);
                    break;
                case 'fields':
                    if (!this.loaded.objects) {
                        this.objects = await getObjectAccess(this.targetParams);
                        this.loaded = { ...this.loaded, objects: true };
                    }
                    this.fields = await getFieldAccess({ ...this.targetParams, sobjectType: this.fieldObject });
                    break;
                case 'permSets':
                    this.permSets = await getAssignments({ ...this.targetParams, kind: 'PermissionSet' });
                    break;
                case 'groups':
                    this.groups = await getAssignments({ ...this.targetParams, kind: 'PermissionSetGroup' });
                    break;
                case 'apps':
                case 'apex':
                case 'flows': {
                    const entityType = ENTITY_TYPES[tab];
                    const items = await getEntityAccess({ ...this.targetParams, entityType });
                    this.entities = { ...this.entities, [entityType]: items };
                    break;
                }
                case 'recordTypes':
                    this.recordTypes = await getRecordTypes();
                    break;
                case 'psUsers':
                    this.psUsers = await getPermSetUsers({ permSetId: this._targetId });
                    break;
                default:
                    break;
            }
            this.loaded = { ...this.loaded, [tab]: true };
        } catch (error) {
            this.toast('Unable to load access', this.errorMessage(error), 'error');
        } finally {
            this._inflight[tab] = false;
            this.busyCount--;
        }
    }

    /** Assignments and saves change inherited access, so every tab except the given one is reloaded on next visit. */
    invalidateOtherTabs(keepTab) {
        const keep = {};
        if (keepTab && this.loaded[keepTab]) {
            keep[keepTab] = true;
        }
        if (this.loaded.recordTypes) {
            keep.recordTypes = true;
        }
        this.loaded = keep;
    }

    // =========================================================================
    // NAVIGATION & FILTERS
    // =========================================================================

    handleNavClick(event) {
        const tab = event.currentTarget.dataset.tab;
        if (tab === this.activeTab) {
            return;
        }
        this.activeTab = tab;
        this.loadTab(tab);
    }

    handleFilterChange(event) {
        const { tab, filter } = event.target.dataset;
        const value = event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.filters = {
            ...this.filters,
            [tab]: { ...this.filters[tab], [filter]: value, limit: PAGE_SIZE }
        };
    }

    handleShowMore(event) {
        const tab = event.target.dataset.tab;
        this.filters = {
            ...this.filters,
            [tab]: { ...this.filters[tab], limit: this.filters[tab].limit + PAGE_SIZE }
        };
    }

    handleOpenFields(event) {
        this.fieldObject = event.currentTarget.dataset.object;
        this.filters = { ...this.filters, fields: newFilters() };
        this.activeTab = 'fields';
        this.loadTab('fields', true);
    }

    handleFieldObjectChange(event) {
        this.fieldObject = event.detail.value;
        this.filters = { ...this.filters, fields: newFilters() };
        this.loadTab('fields', true);
    }

    handleOpenUser(event) {
        this.dispatchEvent(new CustomEvent('openuser', { detail: { userId: event.currentTarget.dataset.id } }));
    }

    handleOpenRecordTypeSetup() {
        const ctx = this.context;
        if (!ctx) {
            return;
        }
        let url = ctx.setupUrl;
        if (this.isUser) {
            url = ctx.editPermSetId
                ? `/lightning/setup/PermSets/page?address=%2F${ctx.editPermSetId}`
                : `/lightning/setup/EnhancedProfiles/page?address=%2F${ctx.profileId}`;
        }
        this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } });
    }

    // =========================================================================
    // OBJECT PERMISSIONS
    // =========================================================================

    ownObjectFlags(item) {
        const pending = this.objChanges[item.sobjectType];
        if (pending) {
            return pending;
        }
        const flags = {};
        OBJECT_PERMS.forEach(p => {
            flags[p.key] = Boolean(item[p.key]);
        });
        return flags;
    }

    handleObjectCheck(event) {
        const { object, perm } = event.target.dataset;
        const checked = event.target.checked;
        const item = this.objects.find(o => o.sobjectType === object);
        if (!item) {
            return;
        }
        const flags = { ...this.ownObjectFlags(item) };
        (checked ? OBJECT_GRANTS[perm] : OBJECT_REVOKES[perm]).forEach(key => {
            flags[key] = checked;
        });

        const changes = { ...this.objChanges };
        const unchanged = OBJECT_PERMS.every(p => flags[p.key] === Boolean(item[p.key]));
        if (unchanged) {
            delete changes[object];
        } else {
            changes[object] = flags;
        }
        this.objChanges = changes;
    }

    get objectFilters() {
        return this.filters.objects;
    }

    get fieldFilters() {
        return this.filters.fields;
    }

    get objectView() {
        const f = this.filters.objects;
        const term = f.search.trim().toLowerCase();
        const canEdit = this.canEditObjects;
        const matches = [];

        for (const item of this.objects) {
            if (f.type === 'standard' && item.isCustom) continue;
            if (f.type === 'custom' && !item.isCustom) continue;
            if (term && !item.label.toLowerCase().includes(term) && !item.sobjectType.toLowerCase().includes(term)) continue;

            const own = this.ownObjectFlags(item);
            const hasAccess = OBJECT_PERMS.some(p => own[p.key] || item[p.inh]);
            if (f.access === 'with' && !hasAccess) continue;
            if (f.access === 'without' && hasAccess) continue;
            matches.push({ item, own });
        }

        const rows = matches.slice(0, f.limit).map(({ item, own }) => ({
            sobjectType: item.sobjectType,
            label: item.label,
            isCustom: item.isCustom,
            sources: item.sources,
            sourcesLabel: item.sources || '—',
            rowClass: this.objChanges[item.sobjectType] ? 'row-dirty' : '',
            cells: OBJECT_PERMS.map(p => {
                const inherited = Boolean(item[p.inh]);
                return {
                    key: p.key,
                    label: p.label,
                    id: `obj-${item.sobjectType}-${p.key}`,
                    checked: own[p.key] || inherited,
                    disabled: !canEdit || inherited,
                    title: inherited ? `${p.label} is granted by: ${item.sources}` : p.label
                };
            })
        }));

        return this.buildView(rows, matches.length, this.objects.length, 'objects');
    }

    // =========================================================================
    // FIELD PERMISSIONS
    // =========================================================================

    ownFieldFlags(item) {
        const pending = this.fieldChanges[item.field];
        return pending
            ? { canRead: pending.canRead, canEdit: pending.canEdit }
            : { canRead: Boolean(item.canRead), canEdit: Boolean(item.canEdit) };
    }

    handleFieldCheck(event) {
        const { field, perm } = event.target.dataset;
        const checked = event.target.checked;
        const item = this.fields.find(f => f.field === field);
        if (!item) {
            return;
        }
        const flags = { ...this.ownFieldFlags(item) };
        if (perm === 'canEdit') {
            flags.canEdit = checked;
            if (checked) flags.canRead = true;
        } else {
            flags.canRead = checked;
            if (!checked) flags.canEdit = false;
        }

        const changes = { ...this.fieldChanges };
        if (flags.canRead === Boolean(item.canRead) && flags.canEdit === Boolean(item.canEdit)) {
            delete changes[field];
        } else {
            changes[field] = { ...flags, sobjectType: this.fieldObject };
        }
        this.fieldChanges = changes;
    }

    get fieldObjectOptions() {
        const options = this.objects.map(o => ({ label: `${o.label} (${o.sobjectType})`, value: o.sobjectType }));
        if (!options.some(o => o.value === this.fieldObject)) {
            options.unshift({ label: this.fieldObject, value: this.fieldObject });
        }
        return options;
    }

    get fieldView() {
        const f = this.filters.fields;
        const term = f.search.trim().toLowerCase();
        const canEdit = this.canEditObjects;
        const matches = [];

        for (const item of this.fields) {
            if (f.type === 'standard' && item.isCustom) continue;
            if (f.type === 'custom' && !item.isCustom) continue;
            if (term && !item.label.toLowerCase().includes(term) && !item.apiName.toLowerCase().includes(term)) continue;

            const own = this.ownFieldFlags(item);
            const hasAccess = own.canRead || item.inhRead;
            if (f.access === 'with' && !hasAccess) continue;
            if (f.access === 'without' && hasAccess) continue;
            matches.push({ item, own });
        }

        const rows = matches.slice(0, f.limit).map(({ item, own }) => ({
            field: item.field,
            apiName: item.apiName,
            label: item.label,
            dataType: item.dataType,
            isCustom: item.isCustom,
            sources: item.sources,
            sourcesLabel: item.sources || '—',
            rowClass: this.fieldChanges[item.field] ? 'row-dirty' : '',
            cells: [
                {
                    key: 'canRead',
                    label: 'Read',
                    id: `fld-${item.field}-read`,
                    checked: own.canRead || item.inhRead,
                    disabled: !canEdit || item.inhRead,
                    title: item.inhRead ? `Read is granted by: ${item.sources}` : 'Read'
                },
                {
                    key: 'canEdit',
                    label: 'Edit',
                    id: `fld-${item.field}-edit`,
                    checked: own.canEdit || item.inhEdit,
                    disabled: !canEdit || item.inhEdit || !item.isEditSupported,
                    title: !item.isEditSupported
                        ? 'This field is read-only (formula or auto-number)'
                        : item.inhEdit ? `Edit is granted by: ${item.sources}` : 'Edit'
                }
            ]
        }));

        return this.buildView(rows, matches.length, this.fields.length, 'fields');
    }

    // =========================================================================
    // PERMISSION SETS / GROUPS
    // =========================================================================

    get assignmentFilters() {
        return this.filters[this.activeTab] || newFilters();
    }

    get assignmentStatusHeader() {
        return this.activeTab === 'groups' ? 'Status' : 'License';
    }

    get assignmentView() {
        const f = this.assignmentFilters;
        const source = this.activeTab === 'groups' ? this.groups : this.permSets;
        const term = f.search.trim().toLowerCase();
        const isUser = this.isUser;

        const matches = source.filter(item => {
            if (term && !(item.label || '').toLowerCase().includes(term) && !(item.apiName || '').toLowerCase().includes(term)) {
                return false;
            }
            if (f.access === 'with' && !item.isAssigned) return false;
            if (f.access === 'without' && item.isAssigned) return false;
            return true;
        });

        const rows = matches.slice(0, f.limit).map(item => {
            const partial = !isUser && item.isAssigned && item.assignedCount < item.totalCount;
            let assignedLabel;
            if (isUser) {
                assignedLabel = item.isAssigned ? 'Assigned' : 'Not assigned';
            } else {
                assignedLabel = `${item.assignedCount} of ${item.totalCount} active users`;
            }
            let badgeClass = 'slds-badge';
            if (item.isAssigned) {
                badgeClass = partial ? 'slds-badge slds-theme_warning' : 'slds-badge slds-theme_success';
            }
            return {
                ...item,
                assignedLabel,
                badgeClass,
                showAssign: isUser ? !item.isAssigned : item.assignedCount < item.totalCount,
                showRemove: item.isAssigned,
                assignLabel: isUser ? 'Assign' : 'Assign to all users',
                removeLabel: isUser ? 'Remove' : 'Remove from all users'
            };
        });

        return this.buildView(rows, matches.length, source.length, this.activeTab);
    }

    async handleAssignment(event) {
        const { id, name } = event.currentTarget.dataset;
        const assign = event.currentTarget.dataset.assign === 'true';
        const kind = this.activeTab === 'groups' ? 'PermissionSetGroup' : 'PermissionSet';
        const kindLabel = this.activeTab === 'groups' ? 'permission set group' : 'permission set';
        const targetName = this.context ? this.context.name : '';

        if (!assign || !this.isUser) {
            const message = this.isUser
                ? `Remove the ${kindLabel} "${name}" from ${targetName}? They lose any access it grants.`
                : assign
                    ? `Assign the ${kindLabel} "${name}" to every active user with the ${targetName} profile?`
                    : `Remove the ${kindLabel} "${name}" from every active user with the ${targetName} profile?`;
            const confirmed = await LightningConfirm.open({
                message,
                label: assign ? 'Assign to all users' : `Remove ${kindLabel}`,
                theme: assign ? 'default' : 'warning'
            });
            if (!confirmed) {
                return;
            }
        }

        this.busyCount++;
        try {
            const res = await setAssignment({ ...this.targetParams, kind, itemId: id, assign });
            this.showResult(res);
            this.invalidateOtherTabs();
            await Promise.all([this.loadContext(), this.loadTab(this.activeTab, true)]);
            this.notifyChange();
        } catch (error) {
            this.toast('Update failed', this.errorMessage(error), 'error');
        } finally {
            this.busyCount--;
        }
    }

    // =========================================================================
    // APPS / APEX CLASSES / FLOWS
    // =========================================================================

    get activeEntityType() {
        return ENTITY_TYPES[this.activeTab];
    }

    get entityFilters() {
        return this.filters[this.activeTab] || newFilters();
    }

    ownEntityEnabled(item) {
        const pending = this.entityChanges[this.activeEntityType][item.id];
        return pending !== undefined ? pending : Boolean(item.isEnabled);
    }

    get entityTypeOptions() {
        const items = this.entities[this.activeEntityType] || [];
        const types = [...new Set(items.map(i => i.typeLabel).filter(Boolean))].sort();
        return [{ label: 'All', value: 'all' }, ...types.map(t => ({ label: t, value: t }))];
    }

    filteredEntities() {
        const f = this.entityFilters;
        const term = f.search.trim().toLowerCase();
        return (this.entities[this.activeEntityType] || []).filter(item => {
            if (f.type !== 'all' && item.typeLabel !== f.type) return false;
            if (term && !(item.label || '').toLowerCase().includes(term) && !(item.apiName || '').toLowerCase().includes(term)) {
                return false;
            }
            const hasAccess = this.ownEntityEnabled(item) || item.isInherited;
            if (f.access === 'with' && !hasAccess) return false;
            if (f.access === 'without' && hasAccess) return false;
            return true;
        });
    }

    get entityView() {
        const entityType = this.activeEntityType;
        const all = this.entities[entityType] || [];
        const matches = this.filteredEntities();
        const pending = this.entityChanges[entityType];

        const rows = matches.slice(0, this.entityFilters.limit).map(item => ({
            ...item,
            checkId: `ent-${item.id}`,
            checked: this.ownEntityEnabled(item) || item.isInherited,
            disabled: item.isInherited,
            title: item.isInherited ? `Granted by: ${item.sources}` : `Access to ${item.label}`,
            sourcesLabel: item.sources || '—',
            rowClass: pending[item.id] !== undefined ? 'row-dirty' : ''
        }));

        return this.buildView(rows, matches.length, all.length, this.activeTab);
    }

    setEntityChange(item, enabled) {
        const entityType = this.activeEntityType;
        const changes = { ...this.entityChanges[entityType] };
        if (enabled === Boolean(item.isEnabled)) {
            delete changes[item.id];
        } else {
            changes[item.id] = enabled;
        }
        return changes;
    }

    handleEntityCheck(event) {
        const id = event.target.dataset.id;
        const item = (this.entities[this.activeEntityType] || []).find(i => i.id === id);
        if (!item) {
            return;
        }
        this.entityChanges = {
            ...this.entityChanges,
            [this.activeEntityType]: this.setEntityChange(item, event.target.checked)
        };
    }

    handleEntityBulk(event) {
        const enabled = event.currentTarget.dataset.enabled === 'true';
        const entityType = this.activeEntityType;
        let changes = { ...this.entityChanges[entityType] };
        this.filteredEntities()
            .filter(item => !item.isInherited)
            .forEach(item => {
                if (enabled === Boolean(item.isEnabled)) {
                    delete changes[item.id];
                } else {
                    changes[item.id] = enabled;
                }
            });
        this.entityChanges = { ...this.entityChanges, [entityType]: changes };
    }

    // =========================================================================
    // RECORD TYPES / PROFILE USERS / SYSTEM PRIVILEGES
    // =========================================================================

    get recordTypeFilters() {
        return this.filters.recordTypes;
    }

    get recordTypeObjectOptions() {
        const objects = [...new Set(this.recordTypes.map(rt => rt.sobjectType))].sort();
        return [{ label: 'All objects', value: 'all' }, ...objects.map(o => ({ label: o, value: o }))];
    }

    get recordTypeRows() {
        const f = this.filters.recordTypes;
        const term = f.search.trim().toLowerCase();
        return this.recordTypes
            .filter(rt => f.type === 'all' || rt.sobjectType === f.type)
            .filter(rt => !term || rt.name.toLowerCase().includes(term) || rt.developerName.toLowerCase().includes(term))
            .map(rt => ({
                ...rt,
                statusLabel: rt.isActive ? 'Active' : 'Inactive',
                badgeClass: rt.isActive ? 'slds-badge slds-theme_success' : 'slds-badge'
            }));
    }

    get recordTypesEmpty() {
        return this.loaded.recordTypes && this.recordTypeRows.length === 0;
    }

    get recordTypeSetupLabel() {
        if (this.isPermissionSet) {
            return 'Open this permission set in Setup';
        }
        if (!this.isUser) {
            return 'Open profile record type settings in Setup';
        }
        return this.context && this.context.editPermSetId
            ? 'Open this user\'s Admin Access permission set in Setup'
            : 'Open this user\'s profile in Setup';
    }

    get profileUsers() {
        return ((this.context && this.context.users) || []).map(u => ({
            ...u,
            badgeClass: u.isActive ? 'slds-badge slds-theme_success' : 'slds-badge'
        }));
    }

    get profileUsersEmpty() {
        return this.profileUsers.length === 0;
    }

    get systemPermissions() {
        return ((this.context && this.context.systemPermissions) || []).map(sp => ({
            ...sp,
            statusLabel: sp.isEnabled ? 'Enabled' : 'Disabled',
            badgeClass: sp.isEnabled ? 'slds-badge slds-theme_success' : 'slds-badge'
        }));
    }

    // =========================================================================
    // PERMISSION SET: ASSIGNED USERS
    // =========================================================================

    get psUsersFilters() {
        return this.filters.psUsers;
    }

    get psUsersView() {
        const f = this.filters.psUsers;
        const term = f.search.trim().toLowerCase();

        const matches = this.psUsers.filter(item => {
            if (term && !(item.label || '').toLowerCase().includes(term)
                && !(item.apiName || '').toLowerCase().includes(term)
                && !(item.description || '').toLowerCase().includes(term)) {
                return false;
            }
            if (f.access === 'with' && !item.isAssigned) return false;
            if (f.access === 'without' && item.isAssigned) return false;
            return true;
        });

        const rows = matches.slice(0, f.limit).map(item => ({
            id: item.id,
            name: item.label,
            username: item.apiName,
            email: item.description,
            profileName: item.typeLabel,
            statusLabel: item.status,
            badgeClass: item.isAssigned ? 'slds-badge slds-theme_success' : 'slds-badge',
            assignedLabel: item.isAssigned ? 'Assigned' : 'Not assigned',
            showAssign: !item.isAssigned,
            showRemove: item.isAssigned
        }));

        return this.buildView(rows, matches.length, this.psUsers.length, 'psUsers');
    }

    async handlePsUserAssignment(event) {
        const { id, name } = event.currentTarget.dataset;
        const assign = event.currentTarget.dataset.assign === 'true';
        const setLabel = this.context ? this.context.name : 'this permission set';

        if (!assign) {
            const confirmed = await LightningConfirm.open({
                message: `Remove "${setLabel}" from ${name}? They lose any access it grants.`,
                label: 'Remove permission set',
                theme: 'warning'
            });
            if (!confirmed) {
                return;
            }
        }

        this.busyCount++;
        try {
            const res = await setPermSetUser({ permSetId: this._targetId, userId: id, assign });
            this.showResult(res);
            await Promise.all([this.loadContext(), this.loadTab('psUsers', true)]);
            this.notifyChange();
        } catch (error) {
            this.toast('Update failed', this.errorMessage(error), 'error');
        } finally {
            this.busyCount--;
        }
    }

    // =========================================================================
    // SAVE / CANCEL
    // =========================================================================

    get pendingCount() {
        const entityCount = Object.values(this.entityChanges).reduce((sum, m) => sum + Object.keys(m).length, 0);
        return Object.keys(this.objChanges).length + Object.keys(this.fieldChanges).length + entityCount;
    }

    get hasPendingChanges() {
        return this.pendingCount > 0;
    }

    get pendingSummary() {
        const n = this.pendingCount;
        return `${n} unsaved change${n === 1 ? '' : 's'}`;
    }

    discardChanges() {
        this.objChanges = {};
        this.fieldChanges = {};
        this.entityChanges = { TabSet: {}, ApexClass: {}, FlowDefinition: {} };
    }

    handleCancelChanges() {
        this.discardChanges();
    }

    async handleSaveChanges() {
        this.isSaving = true;
        this.busyCount++;
        const messages = [];
        const errors = [];

        const run = async (saver, onDone) => {
            try {
                const res = await saver();
                if (res && res.success) {
                    messages.push(res.message);
                } else if (res) {
                    errors.push(res.message, ...(res.errors || []));
                }
                onDone();
            } catch (error) {
                errors.push(this.errorMessage(error));
            }
        };

        const objEntries = Object.entries(this.objChanges);
        if (objEntries.length) {
            const payload = objEntries.map(([sobjectType, flags]) => ({ sobjectType, ...flags }));
            await run(
                () => saveObjectAccess({ ...this.targetParams, changesJson: JSON.stringify(payload) }),
                () => { this.objChanges = {}; }
            );
        }

        const byObject = {};
        Object.entries(this.fieldChanges).forEach(([field, change]) => {
            (byObject[change.sobjectType] = byObject[change.sobjectType] || []).push({
                field,
                canRead: change.canRead,
                canEdit: change.canEdit
            });
        });
        for (const [sobjectType, payload] of Object.entries(byObject)) {
            // eslint-disable-next-line no-await-in-loop
            await run(
                () => saveFieldAccess({ ...this.targetParams, sobjectType, changesJson: JSON.stringify(payload) }),
                () => {
                    const remaining = { ...this.fieldChanges };
                    payload.forEach(p => delete remaining[p.field]);
                    this.fieldChanges = remaining;
                }
            );
        }

        for (const [entityType, changes] of Object.entries(this.entityChanges)) {
            const payload = Object.entries(changes).map(([id, enabled]) => ({ id, enabled }));
            if (!payload.length) continue;
            // eslint-disable-next-line no-await-in-loop
            await run(
                () => saveEntityAccess({ ...this.targetParams, entityType, changesJson: JSON.stringify(payload) }),
                () => { this.entityChanges = { ...this.entityChanges, [entityType]: {} }; }
            );
        }

        if (errors.length) {
            this.toast('Some changes were not saved', errors.slice(0, 4).join('; '), 'warning');
        } else {
            this.toast('Access updated', messages.join(' ') || 'Changes saved.', 'success');
        }

        const current = this.activeTab;
        this.loaded = {};
        await Promise.all([this.loadContext(), this.loadTab(current, true)]);
        this.notifyChange();
        this.isSaving = false;
        this.busyCount--;
    }

    // =========================================================================
    // GETTERS & HELPERS
    // =========================================================================

    get tabs() {
        if (this.isPermissionSet) {
            return PERMSET_TABS;
        }
        return this.isUser ? USER_TABS : PROFILE_TABS;
    }

    get navTabs() {
        return this.tabs.map(tab => ({
            ...tab,
            selected: tab.value === this.activeTab,
            cssClass: tab.value === this.activeTab ? 'cat-pill cat-pill_active' : 'cat-pill',
            iconVariant: tab.value === this.activeTab ? 'inverse' : ''
        }));
    }

    get sectionMeta() {
        const meta = SECTION_META[this.activeTab] || { icon: 'utility:record', title: '', subtitle: '' };
        return { ...meta, subtitle: meta.subtitle.replace('{subject}', this.subjectNoun) };
    }

    get subjectNoun() {
        if (this.isPermissionSet) {
            return this.context ? `the ${this.context.name} permission set` : 'this permission set';
        }
        if (!this.context) {
            return this.isUser ? 'this user' : 'this profile';
        }
        return this.isUser ? this.context.name : `everyone on ${this.context.name}`;
    }

    get isUser() {
        return this._targetType === 'User';
    }

    get isPermissionSet() {
        return this._targetType === 'PermissionSet';
    }

    get isBusy() {
        return this.busyCount > 0;
    }

    get canEditObjects() {
        return Boolean(this.context && this.context.canEditObjectAccess);
    }

    get saveTargetText() {
        const ctx = this.context;
        if (!ctx) {
            return '';
        }
        if (this.isPermissionSet) {
            const users = ctx.activeUserCount === 1 ? '1 user' : `${ctx.activeUserCount} users`;
            return `Changes are saved directly to the "${ctx.name}" permission set, which is currently assigned to ${users}. Use the Assigned Users tab to grant it to more people.`;
        }
        if (this.isUser) {
            const ps = ctx.editPermSetLabel || 'a personal permission set';
            const created = ctx.editPermSetExists ? '' : ' It is created and assigned the first time you save.';
            return `Changes are saved to "${ps}", which is assigned only to ${ctx.name}.${created} Checked boxes you can't clear come from the profile, another permission set or a group; change those at the source.`;
        }
        const users = ctx.activeUserCount === 1 ? '1 active user' : `${ctx.activeUserCount} active users`;
        return `Changes apply to the ${ctx.name} profile and its ${users}.`;
    }

    get isObjectsTab() {
        return this.activeTab === 'objects';
    }

    get isFieldsTab() {
        return this.activeTab === 'fields';
    }

    get isAssignmentTab() {
        return this.activeTab === 'permSets' || this.activeTab === 'groups';
    }

    get isEntityTab() {
        return Boolean(ENTITY_TYPES[this.activeTab]);
    }

    get isFlowsTab() {
        return this.activeTab === 'flows';
    }

    get isRecordTypesTab() {
        return this.activeTab === 'recordTypes';
    }

    get isUsersTab() {
        return this.activeTab === 'users';
    }

    get isSystemTab() {
        return this.activeTab === 'system';
    }

    get isPsUsersTab() {
        return this.activeTab === 'psUsers';
    }

    buildView(rows, matchCount, totalCount, tab) {
        const loaded = Boolean(this.loaded[tab]);
        return {
            rows,
            isEmpty: loaded && rows.length === 0,
            hasMore: matchCount > rows.length,
            summary: loaded
                ? `Showing ${rows.length} of ${matchCount} matching (${totalCount} total)`
                : 'Loading…'
        };
    }

    showResult(res) {
        if (!res) {
            return;
        }
        if (res.success) {
            this.toast('Access updated', res.message, 'success');
        } else {
            this.toast('Some changes were not saved', [res.message, ...(res.errors || [])].slice(0, 4).join('; '), 'warning');
        }
    }

    notifyChange() {
        this.dispatchEvent(new CustomEvent('accesschange'));
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode: variant === 'error' || variant === 'warning' ? 'sticky' : 'dismissible' }));
    }

    errorMessage(error) {
        if (!error) return 'Unknown error.';
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        return JSON.stringify(error);
    }
}

