import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

// Apex Controller Endpoints
import getAdminOverview from '@salesforce/apex/AdminAccessController.getAdminOverview';
import getUsers from '@salesforce/apex/AdminAccessController.getUsers';
import getUserDetail from '@salesforce/apex/AdminAccessController.getUserDetail';
import getPermissionSets from '@salesforce/apex/AdminAccessController.getPermissionSets';
import getPermissionSetDetail from '@salesforce/apex/AdminAccessController.getPermissionSetDetail';
import getPermissionSetGroups from '@salesforce/apex/AdminAccessController.getPermissionSetGroups';
import getPermissionSetGroupDetail from '@salesforce/apex/AdminAccessController.getPermissionSetGroupDetail';
import getProfiles from '@salesforce/apex/AdminAccessController.getProfiles';
import getProfileDetail from '@salesforce/apex/AdminAccessController.getProfileDetail';
import getObjectPermissionsForTarget from '@salesforce/apex/AdminAccessController.getObjectPermissionsForTarget';
import getFieldPermissionsForTarget from '@salesforce/apex/AdminAccessController.getFieldPermissionsForTarget';
import getAppAccessList from '@salesforce/apex/AdminAccessController.getAppAccessList';
import getAccessibleObjects from '@salesforce/apex/AdminAccessController.getAccessibleObjects';

// Mutation Endpoints
import removePermissionSetFromUser from '@salesforce/apex/AdminAccessController.removePermissionSetFromUser';
import removePermissionSetGroupFromUser from '@salesforce/apex/AdminAccessController.removePermissionSetGroupFromUser';
import assignUsersToPermissionSet from '@salesforce/apex/AdminAccessController.assignUsersToPermissionSet';
import removeUsersFromPermissionSet from '@salesforce/apex/AdminAccessController.removeUsersFromPermissionSet';
import assignUsersToPermissionSetGroup from '@salesforce/apex/AdminAccessController.assignUsersToPermissionSetGroup';
import removeUsersFromPermissionSetGroup from '@salesforce/apex/AdminAccessController.removeUsersFromPermissionSetGroup';
import saveObjectPermissions from '@salesforce/apex/AdminAccessController.saveObjectPermissions';
import saveFieldPermissions from '@salesforce/apex/AdminAccessController.saveFieldPermissions';
import toggleUserActiveStatus from '@salesforce/apex/AdminAccessController.toggleUserActiveStatus';
import changeUserProfile from '@salesforce/apex/AdminAccessEditorController.changeUserProfile';

export default class AdminAccess extends NavigationMixin(LightningElement) {
    @track isLoading = false;
    @track activeTab = 'profiles';

    // Overview Stats
    @track overview = {
        totalUsers: 0,
        activeUsers: 0,
        totalPermSets: 0,
        customPermSets: 0,
        totalPermSetGroups: 0,
        totalProfiles: 0,
        totalApps: 0,
        currentAdminName: 'Administrator',
        currentAdminProfile: 'System Administrator',
        isAuthorizedAdmin: true
    };

    // Picklist options
    @track profileOptions = [{ label: 'All Profiles', value: '' }];
    @track statusOptions = [
        { label: 'All Statuses', value: 'All' },
        { label: 'Active', value: 'Active' },
        { label: 'Inactive', value: 'Inactive' }
    ];
    @track psTypeOptions = [
        { label: 'All Types', value: 'All' },
        { label: 'Custom Permission Sets', value: 'Custom' },
        { label: 'Standard Permission Sets', value: 'Standard' }
    ];
    @track psgStatusOptions = [
        { label: 'All Statuses', value: 'All' },
        { label: 'Updated', value: 'Updated' },
        { label: 'Outdated', value: 'Outdated' }
    ];
    @track objectOptions = [];
    @track targetTypeOptions = [
        { label: 'Permission Set', value: 'PermissionSet' },
        { label: 'Profile', value: 'Profile' }
    ];

    // SECTION 1: USERS STATE
    @track userSearchTerm = '';
    @track userProfileFilter = '';
    @track userStatusFilter = 'All';
    @track usersList = [];
    @track selectedUser = null;

    // SECTION 2: PERMISSION SETS STATE
    @track psSearchTerm = '';
    @track psTypeFilter = 'All';
    @track permSetsList = [];
    @track selectedPermSet = null;
    @track selectedPermSetSubTab = 'users';

    // SECTION 3: PERMISSION SET GROUPS STATE
    @track psgSearchTerm = '';
    @track psgStatusFilter = 'All';
    @track groupsList = [];
    @track selectedGroup = null;
    @track selectedGroupSubTab = 'permSets';

    // SECTION 4: PROFILES STATE
    @track profileSearchTerm = '';
    @track profilesList = [];
    @track selectedProfile = null;

    // SECTION 5: OBJECT ACCESS STATE
    @track objTargetType = 'Profile';
    @track objSelectedTargetId = '';
    @track objSearchTerm = '';
    @track objPermItems = [];
    @track objTargetOptions = [];

    // SECTION 6: FIELD-LEVEL SECURITY STATE
    @track flsSelectedObject = 'Account';
    @track flsTargetType = 'PermissionSet';
    @track flsSelectedTargetId = '';
    @track flsSearchTerm = '';
    @track flsFieldItems = [];
    @track flsTargetOptions = [];

    // SECTION 7: APPS STATE
    @track appSearchTerm = '';
    @track appsList = [];

    // MODALS & CONFIRMATION DIALOGS
    @track showConfirmModal = false;
    @track confirmTitle = '';
    @track confirmMessage = '';
    @track confirmItemName = '';
    @track confirmTargetName = '';
    @track confirmActionType = '';
    @track confirmPayload = null;

    @track showAssignModal = false;
    @track assignModalTitle = '';
    @track assignModalType = '';
    @track assignSearchTerm = '';
    @track assignItems = [];
    @track selectedAssignIds = [];

    @track showProfileModal = false;
    @track newProfileId = '';

    @track showEditObjectModal = false;
    @track editObjectData = {};

    @track showEditFieldModal = false;
    @track editFieldData = {};

    connectedCallback() {
        this.loadInitialData();
    }

    async loadInitialData() {
        this.isLoading = true;
        try {
            await Promise.all([
                this.loadOverview(),
                this.loadUsers(),
                this.loadPermissionSets(),
                this.loadGroups(),
                this.loadProfiles(),
                this.loadObjects()
            ]);
        } catch (error) {
            this.showToast('Error', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async refreshAll() {
        this.isLoading = true;
        try {
            await this.loadInitialData();
            if (this.selectedUser) {
                await this.viewUserDetailById(this.selectedUser.user.userId);
            }
            if (this.selectedPermSet) {
                await this.viewPermSetDetailById(this.selectedPermSet.permissionSet.id);
            }
            if (this.selectedGroup) {
                await this.viewGroupDetailById(this.selectedGroup.groupSummary.id);
            }
            if (this.selectedProfile) {
                await this.viewProfileDetailById(this.selectedProfile.profile.id);
            }
            if (this.activeTab === 'objects' && this.objSelectedTargetId) {
                await this.fetchObjectPermissions();
            }
            if (this.activeTab === 'fields' && this.flsSelectedTargetId) {
                await this.fetchFieldPermissions();
            }
            if (this.activeTab === 'apps') {
                await this.loadApps();
            }
            this.showToast('Refreshed', 'Admin Access Console data is up to date.', 'success');
        } catch (error) {
            this.showToast('Refresh Error', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // =========================================================================
    // DATA LOADERS
    // =========================================================================
    async loadOverview() {
        this.overview = await getAdminOverview();
    }

    async loadUsers() {
        const users = await getUsers({
            searchTerm: this.userSearchTerm,
            profileId: this.userProfileFilter,
            statusFilter: this.userStatusFilter
        });
        this.usersList = (users || []).map(u => ({
            ...u,
            statusClass: u.isActive ? 'badge-active' : 'badge-inactive'
        }));
    }

    async loadPermissionSets() {
        const permSets = await getPermissionSets({
            searchTerm: this.psSearchTerm,
            typeFilter: this.psTypeFilter
        });
        this.permSetsList = (permSets || []).map(ps => ({
            ...ps,
            typeClass: ps.isCustom ? 'badge-custom' : 'badge-standard'
        }));
        this.updateTargetDropdowns();
    }

    async loadGroups() {
        const groups = await getPermissionSetGroups({
            searchTerm: this.psgSearchTerm,
            statusFilter: this.psgStatusFilter
        });
        this.groupsList = groups || [];
    }

    async loadProfiles() {
        const profs = await getProfiles({
            searchTerm: this.profileSearchTerm,
            licenseFilter: 'All'
        });
        this.profilesList = profs || [];
        
        const options = [{ label: 'All Profiles', value: '' }];
        for (const p of this.profilesList) {
            options.push({ label: p.name, value: p.id });
        }
        this.profileOptions = options;
        this.updateTargetDropdowns();
    }

    async loadObjects() {
        const objs = await getAccessibleObjects();
        this.objectOptions = objs || [];
    }

    async loadApps() {
        const apps = await getAppAccessList({ searchTerm: this.appSearchTerm });
        this.appsList = (apps || []).map(app => ({
            ...app,
            visibleClass: app.isVisible ? 'badge-active' : 'badge-inactive',
            visibleLabel: app.isVisible ? 'Visible' : 'Hidden',
            accessibleClass: app.isAccessible ? 'badge-active' : 'badge-inactive',
            accessibleLabel: app.isAccessible ? 'Accessible' : 'Restricted'
        }));
    }

    updateTargetDropdowns() {
        if (this.objTargetType === 'PermissionSet') {
            this.objTargetOptions = this.permSetsList.map(ps => ({
                label: ps.label + (ps.isCustom ? ' (Custom)' : ' (Standard)'),
                value: ps.id
            }));
        } else {
            this.objTargetOptions = this.profilesList.map(p => ({
                label: p.name,
                value: p.id
            }));
        }
        if (this.objTargetOptions.length > 0 && !this.objSelectedTargetId) {
            this.objSelectedTargetId = this.objTargetOptions[0].value;
        }

        if (this.flsTargetType === 'PermissionSet') {
            this.flsTargetOptions = this.permSetsList.map(ps => ({
                label: ps.label + (ps.isCustom ? ' (Custom)' : ' (Standard)'),
                value: ps.id
            }));
        } else {
            this.flsTargetOptions = this.profilesList.map(p => ({
                label: p.name,
                value: p.id
            }));
        }
        if (this.flsTargetOptions.length > 0 && !this.flsSelectedTargetId) {
            this.flsSelectedTargetId = this.flsTargetOptions[0].value;
        }
    }

    handleTabChange(event) {
        this.activeTab = event.detail.name || event.detail.value;
        if (this.activeTab === 'apps' && this.appsList.length === 0) {
            this.loadApps();
        } else if (this.activeTab === 'objects' && this.objPermItems.length === 0 && this.objSelectedTargetId) {
            this.fetchObjectPermissions();
        } else if (this.activeTab === 'fields' && this.flsFieldItems.length === 0 && this.flsSelectedTargetId) {
            this.fetchFieldPermissions();
        }
    }

    // =========================================================================
    // SECTION 1: USERS
    // =========================================================================
    handleUserSearch(event) {
        this.userSearchTerm = event.target.value;
        this.loadUsers();
    }

    handleUserProfileFilterChange(event) {
        this.userProfileFilter = event.detail.value;
        this.loadUsers();
    }

    handleUserStatusFilterChange(event) {
        this.userStatusFilter = event.detail.value;
        this.loadUsers();
    }

    async handleViewUserDetail(event) {
        const userId = event.currentTarget.dataset.id;
        await this.viewUserDetailById(userId);
    }

    async viewUserDetailById(userId) {
        this.isLoading = true;
        try {
            const detail = await getUserDetail({ userId });
            if (detail) {
                detail.assignedPermissionSets = (detail.assignedPermissionSets || []).map(ps => ({
                    ...ps,
                    typeClass: ps.isCustom ? 'badge-custom' : 'badge-standard'
                }));
            }
            this.selectedUser = detail;
        } catch (error) {
            this.showToast('Error', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleBackToUsers() {
        this.selectedUser = null;
        this.loadUsers();
    }

    handlePromptToggleUserStatus() {
        const newStatus = !this.selectedUser.user.isActive;
        const actionText = newStatus ? 'activate' : 'deactivate';
        this.confirmTitle = `Confirm User Account Action`;
        this.confirmMessage = `Are you sure you want to ${actionText} the user account for ${this.selectedUser.user.name}?`;
        this.confirmItemName = this.selectedUser.user.name;
        this.confirmTargetName = actionText;
        this.confirmActionType = 'toggleUserStatus';
        this.confirmPayload = { userId: this.selectedUser.user.userId, isActive: newStatus };
        this.showConfirmModal = true;
    }

    // =========================================================================
    // SECTION 2: PERMISSION SETS
    // =========================================================================
    handlePsSearch(event) {
        this.psSearchTerm = event.target.value;
        this.loadPermissionSets();
    }

    handlePsTypeFilterChange(event) {
        this.psTypeFilter = event.detail.value;
        this.loadPermissionSets();
    }

    async handleViewPermSetDetail(event) {
        const psId = event.currentTarget.dataset.id;
        await this.viewPermSetDetailById(psId);
    }

    async viewPermSetDetailById(psId) {
        this.isLoading = true;
        try {
            const detail = await getPermissionSetDetail({ permissionSetId: psId });
            if (detail) {
                detail.assignedUsers = (detail.assignedUsers || []).map(u => ({
                    ...u,
                    statusClass: u.isActive ? 'badge-active' : 'badge-inactive'
                }));
            }
            this.selectedPermSet = detail;
        } catch (error) {
            this.showToast('Error', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleBackToPermSets() {
        this.selectedPermSet = null;
        this.loadPermissionSets();
    }

    handlePermSetSubTabChange(event) {
        this.selectedPermSetSubTab = event.target.value;
    }

    handlePromptAssignUsersToPs() {
        this.assignModalTitle = `Assign Users to ${this.selectedPermSet.permissionSet.label}`;
        this.assignModalType = 'assignUsersToPs';
        this.assignSearchTerm = '';
        this.assignItems = (this.selectedPermSet.availableUsers || []).map(u => ({
            id: u.userId,
            title: u.name,
            subtitle: `${u.username} • Profile: ${u.profileName}`,
            selected: false,
            rowClass: 'selectable-row'
        }));
        this.selectedAssignIds = [];
        this.showAssignModal = true;
    }

    handlePromptRemoveUserFromPs(event) {
        const userId = event.currentTarget.dataset.id;
        const userName = event.currentTarget.dataset.name;
        this.confirmTitle = 'Confirm User Removal';
        this.confirmMessage = `Are you sure you want to remove ${userName} from permission set "${this.selectedPermSet.permissionSet.label}"?`;
        this.confirmItemName = userName;
        this.confirmTargetName = this.selectedPermSet.permissionSet.label;
        this.confirmActionType = 'removeUserFromPs';
        this.confirmPayload = { permSetId: this.selectedPermSet.permissionSet.id, userId };
        this.showConfirmModal = true;
    }

    // =========================================================================
    // SECTION 3: PERMISSION SET GROUPS
    // =========================================================================
    handlePsgSearch(event) {
        this.psgSearchTerm = event.target.value;
        this.loadGroups();
    }

    handlePsgStatusFilterChange(event) {
        this.psgStatusFilter = event.detail.value;
        this.loadGroups();
    }

    async handleViewGroupDetail(event) {
        const groupId = event.currentTarget.dataset.id;
        await this.viewGroupDetailById(groupId);
    }

    async viewGroupDetailById(groupId) {
        this.isLoading = true;
        try {
            const detail = await getPermissionSetGroupDetail({ groupId });
            if (detail) {
                detail.includedPermissionSets = (detail.includedPermissionSets || []).map(ps => ({
                    ...ps,
                    typeClass: ps.isCustom ? 'badge-custom' : 'badge-standard'
                }));
                detail.assignedUsers = (detail.assignedUsers || []).map(u => ({
                    ...u,
                    statusClass: u.isActive ? 'badge-active' : 'badge-inactive'
                }));
            }
            this.selectedGroup = detail;
        } catch (error) {
            this.showToast('Error', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleBackToGroups() {
        this.selectedGroup = null;
        this.loadGroups();
    }

    handleGroupSubTabChange(event) {
        this.selectedGroupSubTab = event.target.value;
    }

    handlePromptAssignUsersToGroup() {
        this.assignModalTitle = `Assign Users to Group ${this.selectedGroup.groupSummary.masterLabel}`;
        this.assignModalType = 'assignUsersToGroup';
        this.assignSearchTerm = '';
        this.assignItems = (this.selectedGroup.availableUsers || []).map(u => ({
            id: u.userId,
            title: u.name,
            subtitle: `${u.username} • Profile: ${u.profileName}`,
            selected: false,
            rowClass: 'selectable-row'
        }));
        this.selectedAssignIds = [];
        this.showAssignModal = true;
    }

    handlePromptRemoveUserFromGroup(event) {
        const userId = event.currentTarget.dataset.id;
        const userName = event.currentTarget.dataset.name;
        this.confirmTitle = 'Confirm Group User Removal';
        this.confirmMessage = `Are you sure you want to remove ${userName} from group "${this.selectedGroup.groupSummary.masterLabel}"?`;
        this.confirmItemName = userName;
        this.confirmTargetName = this.selectedGroup.groupSummary.masterLabel;
        this.confirmActionType = 'removeUserFromGroup';
        this.confirmPayload = { groupId: this.selectedGroup.groupSummary.id, userId };
        this.showConfirmModal = true;
    }

    // =========================================================================
    // SECTION 4: PROFILES
    // =========================================================================
    handleProfileSearch(event) {
        this.profileSearchTerm = event.target.value;
        this.loadProfiles();
    }

    async handleViewProfileDetail(event) {
        const profId = event.currentTarget.dataset.id;
        await this.viewProfileDetailById(profId);
    }

    async viewProfileDetailById(profId) {
        this.isLoading = true;
        try {
            const detail = await getProfileDetail({ profileId: profId });
            if (detail) {
                detail.associatedUsers = (detail.associatedUsers || []).map(u => ({
                    ...u,
                    statusClass: u.isActive ? 'badge-active' : 'badge-inactive'
                }));
                detail.systemPermissions = (detail.systemPermissions || []).map(sp => ({
                    ...sp,
                    statusClass: sp.isEnabled ? 'badge-active' : 'badge-inactive',
                    statusLabel: sp.isEnabled ? 'Enabled' : 'Disabled'
                }));
            }
            this.selectedProfile = detail;
        } catch (error) {
            this.showToast('Error', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleBackToProfiles() {
        this.selectedProfile = null;
        this.loadProfiles();
    }

    // =========================================================================
    // SECTION 5: OBJECT ACCESS
    // =========================================================================
    handleObjTargetTypeChange(event) {
        this.objTargetType = event.detail.value;
        this.objSelectedTargetId = '';
        this.updateTargetDropdowns();
        this.fetchObjectPermissions();
    }

    handleObjTargetChange(event) {
        this.objSelectedTargetId = event.detail.value;
        this.fetchObjectPermissions();
    }

    handleObjSearch(event) {
        this.objSearchTerm = event.target.value;
        this.fetchObjectPermissions();
    }

    async fetchObjectPermissions() {
        if (!this.objSelectedTargetId) return;
        this.isLoading = true;
        try {
            const items = await getObjectPermissionsForTarget({
                parentId: this.objSelectedTargetId,
                targetType: this.objTargetType,
                searchTerm: this.objSearchTerm
            });
            this.objPermItems = (items || []).map(op => ({
                ...op,
                typeClass: op.isCustomObject ? 'badge-custom' : 'badge-standard',
                typeBadge: op.isCustomObject ? 'Custom' : 'Standard'
            }));
        } catch (error) {
            this.showToast('Error', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleOpenEditObject(event) {
        const objType = event.currentTarget.dataset.type;
        const item = this.objPermItems.find(o => o.sobjectType === objType);
        if (item) {
            this.editObjectData = {
                sobjectType: item.sobjectType,
                sobjectLabel: item.sobjectLabel,
                parentId: this.objSelectedTargetId,
                permissionsRead: item.permissionsRead,
                permissionsCreate: item.permissionsCreate,
                permissionsEdit: item.permissionsEdit,
                permissionsDelete: item.permissionsDelete,
                permissionsViewAllRecords: item.permissionsViewAllRecords,
                permissionsModifyAllRecords: item.permissionsModifyAllRecords
            };
            this.showEditObjectModal = true;
        }
    }

    handleCloseEditObjectModal() {
        this.showEditObjectModal = false;
        this.editObjectData = {};
    }

    handleEditObjectCheckbox(event) {
        const field = event.target.name;
        this.editObjectData[field] = event.target.checked;
        if (event.target.checked && (field === 'permissionsCreate' || field === 'permissionsEdit' || field === 'permissionsDelete' || field === 'permissionsViewAllRecords' || field === 'permissionsModifyAllRecords')) {
            this.editObjectData.permissionsRead = true;
        }
        if (event.target.checked && field === 'permissionsModifyAllRecords') {
            this.editObjectData.permissionsViewAllRecords = true;
            this.editObjectData.permissionsEdit = true;
            this.editObjectData.permissionsDelete = true;
        }
    }

    async handleSaveObjectPermissions() {
        this.isLoading = true;
        try {
            const res = await saveObjectPermissions({
                permissionSetId: this.editObjectData.parentId,
                sobjectType: this.editObjectData.sobjectType,
                canRead: this.editObjectData.permissionsRead,
                canCreate: this.editObjectData.permissionsCreate,
                canEdit: this.editObjectData.permissionsEdit,
                canDelete: this.editObjectData.permissionsDelete,
                canViewAll: this.editObjectData.permissionsViewAllRecords,
                canModifyAll: this.editObjectData.permissionsModifyAllRecords
            });
            this.showToast('Success', res.message, 'success');
            this.showEditObjectModal = false;
            await this.fetchObjectPermissions();
        } catch (error) {
            this.showToast('Save Failed', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // =========================================================================
    // SECTION 6: FIELD ACCESS (FLS)
    // =========================================================================
    handleFlsObjectChange(event) {
        this.flsSelectedObject = event.detail.value;
        this.fetchFieldPermissions();
    }

    handleFlsTargetTypeChange(event) {
        this.flsTargetType = event.detail.value;
        this.flsSelectedTargetId = '';
        this.updateTargetDropdowns();
        this.fetchFieldPermissions();
    }

    handleFlsTargetChange(event) {
        this.flsSelectedTargetId = event.detail.value;
        this.fetchFieldPermissions();
    }

    handleFlsSearch(event) {
        this.flsSearchTerm = event.target.value;
        this.fetchFieldPermissions();
    }

    async fetchFieldPermissions() {
        if (!this.flsSelectedTargetId || !this.flsSelectedObject) return;
        this.isLoading = true;
        try {
            const items = await getFieldPermissionsForTarget({
                parentId: this.flsSelectedTargetId,
                targetType: this.flsTargetType,
                sobjectType: this.flsSelectedObject,
                searchTerm: this.flsSearchTerm
            });
            this.flsFieldItems = (items || []).map(fp => ({
                ...fp,
                typeClass: fp.isCustom ? 'badge-custom' : 'badge-standard',
                typeBadge: fp.isCustom ? 'Custom' : 'Standard'
            }));
        } catch (error) {
            this.showToast('Error', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleOpenEditField(event) {
        const fieldName = event.currentTarget.dataset.field;
        const item = this.flsFieldItems.find(f => f.field === fieldName);
        if (item) {
            this.editFieldData = {
                field: item.field,
                fieldLabel: item.fieldLabel,
                sobjectType: item.sobjectType,
                parentId: this.flsSelectedTargetId,
                permissionsRead: item.permissionsRead,
                permissionsEdit: item.permissionsEdit
            };
            this.showEditFieldModal = true;
        }
    }

    handleCloseEditFieldModal() {
        this.showEditFieldModal = false;
        this.editFieldData = {};
    }

    handleEditFieldCheckbox(event) {
        const field = event.target.name;
        this.editFieldData[field] = event.target.checked;
        if (event.target.checked && field === 'permissionsEdit') {
            this.editFieldData.permissionsRead = true;
        }
    }

    async handleSaveFieldPermissions() {
        this.isLoading = true;
        try {
            const res = await saveFieldPermissions({
                permissionSetId: this.editFieldData.parentId,
                sobjectType: this.editFieldData.sobjectType,
                fieldApiName: this.editFieldData.field,
                canRead: this.editFieldData.permissionsRead,
                canEdit: this.editFieldData.permissionsEdit
            });
            this.showToast('Success', res.message, 'success');
            this.showEditFieldModal = false;
            await this.fetchFieldPermissions();
        } catch (error) {
            this.showToast('Save Failed', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // =========================================================================
    // SECTION 7: APPS
    // =========================================================================
    handleAppSearch(event) {
        this.appSearchTerm = event.target.value;
        this.loadApps();
    }

    // =========================================================================
    // MODAL DIALOG HANDLERS
    // =========================================================================
    handleCloseConfirmModal() {
        this.showConfirmModal = false;
        this.confirmPayload = null;
    }

    async handleExecuteConfirmAction() {
        this.isLoading = true;
        this.showConfirmModal = false;

        try {
            let res;
            switch (this.confirmActionType) {
                case 'toggleUserStatus':
                    res = await toggleUserActiveStatus({
                        userId: this.confirmPayload.userId,
                        isActive: this.confirmPayload.isActive
                    });
                    this.showToast('Success', res.message, 'success');
                    await this.viewUserDetailById(this.confirmPayload.userId);
                    break;

                case 'removeUserFromPs':
                    res = await removePermissionSetFromUser({
                        userId: this.confirmPayload.userId,
                        permissionSetId: this.confirmPayload.permSetId
                    });
                    this.showToast('Success', res.message, 'success');
                    await this.viewPermSetDetailById(this.confirmPayload.permSetId);
                    break;

                case 'removeUserFromGroup':
                    res = await removePermissionSetGroupFromUser({
                        userId: this.confirmPayload.userId,
                        permissionSetGroupId: this.confirmPayload.groupId
                    });
                    this.showToast('Success', res.message, 'success');
                    await this.viewGroupDetailById(this.confirmPayload.groupId);
                    break;
            }
        } catch (error) {
            this.showToast('Action Failed', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCloseAssignModal() {
        this.showAssignModal = false;
        this.assignItems = [];
        this.selectedAssignIds = [];
    }

    handleAssignItemToggle(event) {
        const itemId = event.currentTarget.dataset.id;
        this.assignItems = this.assignItems.map(item => {
            if (item.id === itemId) {
                const newSelected = !item.selected;
                return {
                    ...item,
                    selected: newSelected,
                    rowClass: newSelected ? 'selectable-row selected' : 'selectable-row'
                };
            }
            return item;
        });

        const selected = this.assignItems.filter(i => i.selected).map(i => i.id);
        this.selectedAssignIds = selected;
    }

    handleAssignModalSearch(event) {
        const term = event.target.value.toLowerCase();
        this.assignSearchTerm = term;
    }

    get filteredAssignItems() {
        if (!this.assignSearchTerm) {
            return this.assignItems;
        }
        return this.assignItems.filter(i =>
            (i.title && i.title.toLowerCase().includes(this.assignSearchTerm)) ||
            (i.subtitle && i.subtitle.toLowerCase().includes(this.assignSearchTerm))
        );
    }

    async handleExecuteAssignAction() {
        if (this.selectedAssignIds.length === 0) {
            this.showToast('Selection Required', 'Please select at least one item to assign.', 'warning');
            return;
        }

        this.isLoading = true;
        this.showAssignModal = false;

        try {
            let res;
            switch (this.assignModalType) {
                case 'assignUsersToPs':
                    res = await assignUsersToPermissionSet({
                        permissionSetId: this.selectedPermSet.permissionSet.id,
                        userIds: this.selectedAssignIds
                    });
                    this.showToast('Success', res.message, 'success');
                    await this.viewPermSetDetailById(this.selectedPermSet.permissionSet.id);
                    break;

                case 'assignUsersToGroup':
                    res = await assignUsersToPermissionSetGroup({
                        permissionSetGroupId: this.selectedGroup.groupSummary.id,
                        userIds: this.selectedAssignIds
                    });
                    this.showToast('Success', res.message, 'success');
                    await this.viewGroupDetailById(this.selectedGroup.groupSummary.id);
                    break;
            }
        } catch (error) {
            this.showToast('Assignment Error', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // =========================================================================
    // COMPUTED GETTERS
    // =========================================================================
    get navItems() {
        return [
            { name: 'profiles', value: 'profiles', label: 'Profiles', icon: 'utility:identity' },
            { name: 'users', value: 'users', label: 'Users', icon: 'utility:user' },
            { name: 'permSets', value: 'permSets', label: 'Permission Sets', icon: 'utility:lock' },
            { name: 'groups', value: 'groups', label: 'Permission Set Groups', icon: 'utility:groups' },
            { name: 'objects', value: 'objects', label: 'Object Access', icon: 'utility:database' },
            { name: 'fields', value: 'fields', label: 'Field-Level Security', icon: 'utility:shield' }
        ];
    }

    get isUsersTab() {
        return this.activeTab === 'users';
    }

    get isPermSetsTab() {
        return this.activeTab === 'permSets';
    }

    get isGroupsTab() {
        return this.activeTab === 'groups';
    }

    get isProfilesTab() {
        return this.activeTab === 'profiles';
    }

    get isObjectsTab() {
        return this.activeTab === 'objects';
    }

    get isFieldsTab() {
        return this.activeTab === 'fields';
    }

    get isAppsTab() {
        return this.activeTab === 'apps';
    }

    get isObjTargetCustom() {
        return this.objTargetType === 'PermissionSet';
    }

    get isFlsTargetCustom() {
        return this.flsTargetType === 'PermissionSet';
    }

    get assignSaveDisabled() {
        return !this.selectedAssignIds || this.selectedAssignIds.length === 0;
    }

    get selectedUserBadgeClass() {
        return this.selectedUser && this.selectedUser.user && this.selectedUser.user.isActive
            ? 'slds-badge slds-theme_success'
            : 'slds-badge';
    }

    get toggleUserBtnLabel() {
        if (!this.selectedUser || !this.selectedUser.user) return 'Activate';
        return this.selectedUser.user.isActive ? 'Deactivate User' : 'Activate User';
    }

    get toggleUserBtnIcon() {
        if (!this.selectedUser || !this.selectedUser.user) return 'utility:check';
        return this.selectedUser.user.isActive ? 'utility:ban' : 'utility:check';
    }

    get selectedPermSetTypeClass() {
        if (!this.selectedPermSet || !this.selectedPermSet.permissionSet) return 'badge-standard';
        return this.selectedPermSet.permissionSet.isCustom ? 'badge-custom' : 'badge-standard';
    }

    get selectedPermSetEditableClass() {
        if (!this.selectedPermSet || !this.selectedPermSet.permissionSet) return 'badge-metadata';
        return this.selectedPermSet.permissionSet.isEditable ? 'badge-editable' : 'badge-metadata';
    }

    get selectedPermSetEditableLabel() {
        if (!this.selectedPermSet || !this.selectedPermSet.permissionSet) return 'View Only (Metadata Managed)';
        return this.selectedPermSet.permissionSet.isEditable ? 'Editable' : 'View Only (Metadata Managed)';
    }

    get hasPermSetAssignedUsers() {
        return Boolean(this.selectedPermSet?.assignedUsers?.length);
    }

    get hasPermSetObjectPerms() {
        return Boolean(this.selectedPermSet?.objectPermissions?.length);
    }

    get hasPermSetFieldPerms() {
        return Boolean(this.selectedPermSet?.fieldPermissions?.length);
    }

    get hasGroupAssignedUsers() {
        return Boolean(this.selectedGroup?.assignedUsers?.length);
    }

    get hasObjPermItems() {
        return Boolean(this.objPermItems?.length);
    }

    get hasFlsFieldItems() {
        return Boolean(this.flsFieldItems?.length);
    }

    get hasFilteredAssignItems() {
        return Boolean(this.filteredAssignItems?.length);
    }

    // =========================================================================
    // HEADER, SETUP LINKS & ACCESS EDITOR
    // =========================================================================
    get headerStats() {
        const o = this.overview || {};
        return [
            { tab: 'profiles', label: 'Profiles', value: o.totalProfiles, meta: 'Baseline access', title: 'Open Profiles' },
            { tab: 'users', label: 'Users', value: o.totalUsers, meta: `${o.activeUsers} active`, title: 'Open Users' },
            { tab: 'permSets', label: 'Permission Sets', value: o.totalPermSets, meta: `${o.customPermSets} custom`, title: 'Open Permission Sets' },
            { tab: 'groups', label: 'Permission Set Groups', value: o.totalPermSetGroups, meta: 'Bundled access', title: 'Open Permission Set Groups' },
            { tab: 'apps', label: 'Apps', value: o.totalApps, meta: 'Lightning and connected', title: 'Open App Security' }
        ];
    }

    handleStatClick(event) {
        this.handleTabChange({ detail: { name: event.currentTarget.dataset.tab } });
    }

    navigateToUrl(url) {
        this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } });
    }

    handleOpenSetupHome() {
        this.navigateToUrl('/lightning/setup/SetupOneHome/home');
    }

    handleOpenUserSetup() {
        const userId = this.selectedUser.user.userId;
        this.navigateToUrl(`/lightning/setup/ManageUsers/page?address=%2F${userId}%3Fnoredirect%3D1`);
    }

    handleOpenProfileSetup() {
        this.navigateToUrl(`/lightning/setup/EnhancedProfiles/page?address=%2F${this.selectedProfile.profile.id}`);
    }

    async handleOpenUserProfile() {
        const profileId = this.selectedUser.user.profileId;
        this.activeTab = 'profiles';
        await this.viewProfileDetailById(profileId);
    }

    async handleEditorOpenUser(event) {
        this.activeTab = 'users';
        await this.viewUserDetailById(event.detail.userId);
    }

    handleEditorAccessChange() {
        // Keep list counts and header stats current without blocking the editor
        Promise.all([this.loadOverview(), this.loadUsers()]).catch(() => {});
    }

    get assignableProfileOptions() {
        return this.profileOptions.filter(o => o.value);
    }

    get profileSaveDisabled() {
        return !this.newProfileId || (this.selectedUser && this.newProfileId === this.selectedUser.user.profileId);
    }

    handleOpenProfileModal() {
        this.newProfileId = this.selectedUser.user.profileId;
        this.showProfileModal = true;
    }

    handleCloseProfileModal() {
        this.showProfileModal = false;
    }

    handleNewProfileChange(event) {
        this.newProfileId = event.detail.value;
    }

    async handleSaveUserProfile() {
        const userId = this.selectedUser.user.userId;
        this.showProfileModal = false;
        this.isLoading = true;
        try {
            const res = await changeUserProfile({ userId, profileId: this.newProfileId });
            this.showToast('Profile updated', res.message, 'success');
            await this.viewUserDetailById(userId);
            this.handleEditorAccessChange();
        } catch (error) {
            this.showToast('Profile not changed', this.extractErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractErrorMessage(error) {
        if (!error) return 'Unknown error occurred.';
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        return JSON.stringify(error);
    }
}
