import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { NavigationMixin } from "lightning/navigation";

// Apex Controller Endpoints
import getAdminOverview from "@salesforce/apex/AdminAccessController.getAdminOverview";
import getUsers from "@salesforce/apex/AdminAccessController.getUsers";
import getUserDetail from "@salesforce/apex/AdminAccessController.getUserDetail";
import getPermissionSets from "@salesforce/apex/AdminAccessController.getPermissionSets";
import getPermissionSetDetail from "@salesforce/apex/AdminAccessController.getPermissionSetDetail";
import getPermissionSetGroups from "@salesforce/apex/AdminAccessController.getPermissionSetGroups";
import getPermissionSetGroupDetail from "@salesforce/apex/AdminAccessController.getPermissionSetGroupDetail";
import getProfiles from "@salesforce/apex/AdminAccessController.getProfiles";
import getProfileDetail from "@salesforce/apex/AdminAccessController.getProfileDetail";
import getObjectPermissionsForTarget from "@salesforce/apex/AdminAccessController.getObjectPermissionsForTarget";
import getFieldPermissionsForTarget from "@salesforce/apex/AdminAccessController.getFieldPermissionsForTarget";
import getAppAccessList from "@salesforce/apex/AdminAccessController.getAppAccessList";
import getAppDetail from "@salesforce/apex/AdminAccessController.getAppDetail";
import getAppObjectFields from "@salesforce/apex/AdminAccessController.getAppObjectFields";
import assignProfileToApp from "@salesforce/apex/AdminAccessController.assignProfileToApp";
import removeProfileFromApp from "@salesforce/apex/AdminAccessController.removeProfileFromApp";
import getAccessibleObjects from "@salesforce/apex/AdminAccessController.getAccessibleObjects";
import getUserOptions from "@salesforce/apex/AdminAccessController.getUserOptions";

// Mutation Endpoints
import removePermissionSetFromUser from "@salesforce/apex/AdminAccessController.removePermissionSetFromUser";
import removePermissionSetGroupFromUser from "@salesforce/apex/AdminAccessController.removePermissionSetGroupFromUser";
import assignUsersToPermissionSet from "@salesforce/apex/AdminAccessController.assignUsersToPermissionSet";
import assignUsersToPermissionSetGroup from "@salesforce/apex/AdminAccessController.assignUsersToPermissionSetGroup";
import saveObjectPermissions from "@salesforce/apex/AdminAccessController.saveObjectPermissions";
import saveFieldPermissions from "@salesforce/apex/AdminAccessController.saveFieldPermissions";
import toggleUserActiveStatus from "@salesforce/apex/AdminAccessController.toggleUserActiveStatus";
import changeUserProfile from "@salesforce/apex/AdminAccessEditorController.changeUserProfile";
import createPermissionSet from "@salesforce/apex/AdminAccessEditorController.createPermissionSet";
import getUserLicenseOptions from "@salesforce/apex/AdminAccessEditorController.getUserLicenseOptions";
import createUser from "@salesforce/apex/AdminAccessController.createUser";
import createPermissionSetGroup from "@salesforce/apex/AdminAccessController.createPermissionSetGroup";
import addPermissionSetsToGroup from "@salesforce/apex/AdminAccessController.addPermissionSetsToGroup";
import removePermissionSetFromGroup from "@salesforce/apex/AdminAccessController.removePermissionSetFromGroup";

const PAGE_SIZE = 15;

export default class AdminAccess extends NavigationMixin(LightningElement) {
  @track isLoading = false;
  @track activeTab = "userAndProfile";
  @track userProfileSubTab = "profile"; // 'profile' or 'user' (default 'profile')

  // Current page (1-based) and total record count for each paginated list
  @track pages = { users: 1, permSets: 1, objects: 1, fls: 1 };
  @track totals = { users: 0, permSets: 0, objects: 0, fls: 0 };
  // Full permission-set list for the Object/FLS target dropdowns (not paginated)
  @track permSetOptionsAll = [];

  // Overview Stats
  @track overview = {
    totalUsers: 0,
    activeUsers: 0,
    totalPermSets: 0,
    customPermSets: 0,
    totalPermSetGroups: 0,
    totalProfiles: 0,
    totalApps: 0,
    currentAdminName: "Administrator",
    currentAdminProfile: "System Administrator",
    isAuthorizedAdmin: true
  };

  // Picklist options
  @track profileOptions = [{ label: "All Profiles", value: "" }];
  @track statusOptions = [
    { label: "All Statuses", value: "All" },
    { label: "Active", value: "Active" },
    { label: "Inactive", value: "Inactive" }
  ];
  @track psTypeOptions = [
    { label: "All Types", value: "All" },
    { label: "Custom Permission Sets", value: "Custom" },
    { label: "Standard Permission Sets", value: "Standard" }
  ];
  @track psgStatusOptions = [
    { label: "All Statuses", value: "All" },
    { label: "Updated", value: "Updated" },
    { label: "Outdated", value: "Outdated" }
  ];
  @track objectOptions = [];
  @track targetTypeOptions = [
    { label: "Profile", value: "Profile" },
    { label: "User", value: "User" },
    { label: "Permission Set", value: "PermissionSet" }
  ];

  // SECTION 1: USERS STATE
  @track userSearchTerm = "";
  @track userProfileFilter = "";
  @track userStatusFilter = "All";
  @track usersList = [];
  @track selectedUser = null;

  // SECTION 2: PERMISSION SETS STATE
  @track psSearchTerm = "";
  @track psTypeFilter = "Custom";
  @track permSetsList = [];
  @track selectedPermSet = null;
  @track selectedPermSetSubTab = "users";

  // SECTION 3: PERMISSION SET GROUPS STATE
  @track psgSearchTerm = "";
  @track psgStatusFilter = "All";
  @track psgTypeFilter = "Custom";
  @track psgTypeOptions = [
    { label: "All Groups", value: "All" },
    { label: "Custom Groups", value: "Custom" },
    { label: "Standard Groups", value: "Standard" }
  ];
  allGroupsList = [];
  @track groupsList = [];
  @track selectedGroup = null;
  @track selectedGroupSubTab = "permSets";

  // SECTION 4: PROFILES STATE
  @track profileSearchTerm = "";
  @track profileTypeFilter = "All";
  @track profileTypeOptions = [
    { label: "All Profiles", value: "All" },
    { label: "Custom Profiles", value: "Custom" },
    { label: "Standard Profiles", value: "Standard" }
  ];
  @track profilesList = [];
  @track selectedProfile = null;

  // SECTION 5: OBJECT ACCESS STATE
  @track objTargetType = "Profile";
  @track objSelectedTargetId = "";
  @track objProfileFilter = "";
  @track objSearchTerm = "";
  @track objPermItems = [];
  @track objTargetOptions = [];

  // SECTION 6: FIELD-LEVEL SECURITY STATE
  @track flsSelectedObject = "Account";
  @track flsTargetType = "Profile";
  @track flsSelectedTargetId = "";
  @track flsProfileFilter = "";
  @track flsSearchTerm = "";
  @track flsFieldItems = [];
  @track flsTargetOptions = [];
  allUserOptions = [];

  // SECTION 7: APPS STATE
  @track appSearchTerm = "";
  @track appTypeFilter = "All";
  @track appNavFilter = "All";
  @track allAppsList = [];
  @track appsList = [];
  @track filteredAppsList = [];
  @track isAppsLoading = false;
  @track selectedApp = null;
  @track selectedAppDetail = null;
  @track isAppDetailLoading = false;
  @track appTabSearchTerm = "";
  @track appObjectSearchTerm = "";
  @track appProfileSearchTerm = "";
  @track appProfileFilter = "All";
  @track selectedAppTab = "tabs";
  @track activeObjectFields = null;
  @track activeObjectForFields = null;
  @track isLoadingObjectFields = false;
  @track showObjectFieldsModal = false;
  @track objectFieldSearchTerm = "";

  // MODALS & CONFIRMATION DIALOGS
  @track showConfirmModal = false;
  @track confirmTitle = "";
  @track confirmMessage = "";
  @track confirmItemName = "";
  @track confirmTargetName = "";
  @track confirmActionType = "";
  @track confirmPayload = null;

  @track showAssignModal = false;
  @track assignModalTitle = "";
  @track assignModalType = "";
  @track assignSearchTerm = "";
  @track assignItems = [];
  @track selectedAssignIds = [];

  @track showProfileModal = false;
  @track newProfileId = "";

  @track showEditObjectModal = false;
  @track editObjectData = {};

  @track showEditFieldModal = false;
  @track editFieldData = {};

  // CREATE PERMISSION SET + FULL EDITOR
  @track showCreatePsModal = false;
  @track newPs = { label: "", apiName: "", licenseId: "", description: "" };
  @track licenseOptions = [];
  @track editingPermSetId = null;
  @track editingPermSetLabel = "";
  @track editingPermSetInitialTab = "objects";
  pendingEditorTab = "objects";

  // CREATE PERMISSION SET GROUP
  @track showCreatePsgModal = false;
  @track newPsg = { masterLabel: "", developerName: "", description: "" };

  // CREATE USER
  @track showCreateUserModal = false;
  @track newUser = {
    firstName: "",
    lastName: "",
    email: "",
    username: "",
    alias: "",
    profileId: ""
  };

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
        this.loadPermSetOptions(),
        this.loadGroups(),
        this.loadProfiles(),
        this.loadObjects(),
        this.loadUserOptions(),
        this.loadApps()
      ]);
    } catch (error) {
      this.showToast("Error", this.extractErrorMessage(error), "error");
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
      if (this.activeTab === "objects" && this.objSelectedTargetId) {
        await this.fetchObjectPermissions();
      }
      if (this.activeTab === "fields" && this.flsSelectedTargetId) {
        await this.fetchFieldPermissions();
      }
      if (this.activeTab === "apps") {
        await this.loadApps();
      }
      this.showToast(
        "Refreshed",
        "Admin Access Console data is up to date.",
        "success"
      );
    } catch (error) {
      this.showToast("Refresh Error", this.extractErrorMessage(error), "error");
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

  async loadUsers(resetPage = true) {
    if (resetPage) {
      this.pages = { ...this.pages, users: 1 };
    }
    const res = await getUsers({
      searchTerm: this.userSearchTerm,
      profileId: this.userProfileFilter,
      statusFilter: this.userStatusFilter,
      pageNumber: this.pages.users,
      pageSize: PAGE_SIZE
    });
    this.usersList = ((res && res.records) || []).map((u) => ({
      ...u,
      statusClass: u.isActive ? "badge-active" : "badge-inactive"
    }));
    this.totals = { ...this.totals, users: res ? res.totalCount : 0 };
  }

  async loadPermissionSets(resetPage = true) {
    if (resetPage) {
      this.pages = { ...this.pages, permSets: 1 };
    }
    const res = await getPermissionSets({
      searchTerm: this.psSearchTerm,
      typeFilter: this.psTypeFilter,
      pageNumber: this.pages.permSets,
      pageSize: PAGE_SIZE
    });
    this.permSetsList = ((res && res.records) || []).map((ps) => ({
      ...ps,
      typeClass: ps.isCustom ? "badge-custom" : "badge-standard"
    }));
    this.totals = { ...this.totals, permSets: res ? res.totalCount : 0 };
    this.updateTargetDropdowns();
  }

  // Full permission-set list (id + label) for the Object/FLS target dropdowns.
  async loadPermSetOptions() {
    const res = await getPermissionSets({
      searchTerm: "",
      typeFilter: "All",
      pageNumber: 1,
      pageSize: 2000
    });
    this.permSetOptionsAll = (res && res.records) || [];
    this.updateTargetDropdowns();
  }

  async loadGroups() {
    const groups = await getPermissionSetGroups({
      searchTerm: this.psgSearchTerm,
      statusFilter: this.psgStatusFilter
    });
    this.allGroupsList = (groups || []).map((g) => ({
      ...g,
      typeLabel: g.isCustom ? "Custom" : "Standard",
      typeClass: g.isCustom ? "badge-custom" : "badge-standard"
    }));
    this.applyGroupFilters();
  }

  applyGroupFilters() {
    if (this.psgTypeFilter === "Custom") {
      this.groupsList = this.allGroupsList.filter((g) => g.isCustom);
    } else if (this.psgTypeFilter === "Standard") {
      this.groupsList = this.allGroupsList.filter((g) => !g.isCustom);
    } else {
      this.groupsList = this.allGroupsList;
    }
  }

  handlePsgTypeFilterChange(event) {
    this.psgTypeFilter = event.detail.value;
    this.applyGroupFilters();
  }

  async loadProfiles() {
    const profs = await getProfiles({
      searchTerm: this.profileSearchTerm,
      licenseFilter: "All"
    });
    const mapped = (profs || []).map((p) => ({
      ...p,
      typeLabel: p.isCustom ? "Custom" : "Standard",
      typeClass: p.isCustom ? "badge-custom" : "badge-standard"
    }));

    if (this.profileTypeFilter === "Custom") {
      this.profilesList = mapped.filter((p) => p.isCustom);
    } else if (this.profileTypeFilter === "Standard") {
      this.profilesList = mapped.filter((p) => !p.isCustom);
    } else {
      this.profilesList = mapped;
    }

    const options = [{ label: "All Profiles", value: "" }];
    for (const p of mapped) {
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
    this.isAppsLoading = true;
    try {
      const apps = await getAppAccessList({ searchTerm: "" });
      this.allAppsList = (apps || []).map((app) => ({
        ...app,
        typeBadgeClass: app.isCustom ? "badge-custom" : "badge-standard",
        typeBadgeLabel: app.isCustom ? "Custom" : "Standard",
        avatarStyle: `background-color: ${app.headerColor || "#0176D3"};`,
        visibleClass: app.isVisible ? "badge-active" : "badge-inactive",
        visibleLabel: app.isVisible ? "Visible" : "Hidden",
        accessibleClass: app.isAccessible ? "badge-active" : "badge-inactive",
        accessibleLabel: app.isAccessible ? "Accessible" : "Restricted"
      }));
      this.applyAppFilters();
    } catch (err) {
      console.error("Error loading apps", err);
      this.showToast("Error", this.extractErrorMessage(err), "error");
    } finally {
      this.isAppsLoading = false;
    }
  }

  get appTypeOptions() {
    return [
      { label: "All Types", value: "All" },
      { label: "Custom Apps", value: "Custom" },
      { label: "Standard Apps", value: "Standard" }
    ];
  }

  get appNavOptions() {
    return [
      { label: "All Navigation Types", value: "All" },
      { label: "Standard Navigation", value: "Standard" },
      { label: "Console Navigation", value: "Console" }
    ];
  }

  handleAppTypeFilter(event) {
    this.appTypeFilter = event.detail.value;
    this.applyAppFilters();
  }

  handleAppNavFilter(event) {
    this.appNavFilter = event.detail.value;
    this.applyAppFilters();
  }

  handleAppSearch(event) {
    this.appSearchTerm = event.target.value;
    this.applyAppFilters();
  }

  applyAppFilters() {
    if (!this.allAppsList) {
      this.filteredAppsList = [];
      this.appsList = [];
      return;
    }
    const term = (this.appSearchTerm || "").toLowerCase().trim();
    this.filteredAppsList = this.allAppsList.filter((app) => {
      if (this.appTypeFilter === "Custom" && !app.isCustom) return false;
      if (this.appTypeFilter === "Standard" && app.isCustom) return false;

      if (this.appNavFilter === "Console" && app.navType !== "Console") return false;
      if (this.appNavFilter === "Standard" && app.navType !== "Standard") return false;

      if (term) {
        const label = (app.label || "").toLowerCase();
        const devName = (app.developerName || "").toLowerCase();
        const desc = (app.description || "").toLowerCase();
        return (
          label.includes(term) ||
          devName.includes(term) ||
          desc.includes(term)
        );
      }
      return true;
    });
    this.appsList = this.filteredAppsList;
  }

  get filteredAppsCount() {
    return this.filteredAppsList ? this.filteredAppsList.length : 0;
  }

  get totalAppsCount() {
    return this.allAppsList ? this.allAppsList.length : 0;
  }

  get isFilteredAppsEmpty() {
    return !this.filteredAppsList || this.filteredAppsList.length === 0;
  }

  get isAppDetailView() {
    return Boolean(this.selectedApp);
  }

  get isAppListView() {
    return !this.selectedApp;
  }

  async handleSelectApp(event) {
    let appId;
    if (typeof event === "string") {
      appId = event;
    } else if (event && event.currentTarget) {
      appId = event.currentTarget.dataset.id || event.currentTarget.getAttribute("data-id");
    } else if (event && event.target) {
      appId = event.target.dataset.id || event.target.getAttribute("data-id");
    }

    if (!appId) {
      console.warn("handleSelectApp: missing appId from click event", event);
      return;
    }

    const selected = (this.allAppsList || []).find(
      (a) => a.id === appId || a.applicationId === appId || a.appDefinitionId === appId
    );
    if (!selected) {
      console.warn("handleSelectApp: app not found for id", appId);
      return;
    }

    this.selectedApp = selected;
    this.selectedAppDetail = null;
    this.selectedAppTab = "tabs";
    this.appTabSearchTerm = "";
    this.appObjectSearchTerm = "";
    this.appProfileSearchTerm = "";
    this.appProfileFilter = "All";
    await this.loadAppDetail(selected.applicationId, selected.appDefinitionId);
  }

  async loadAppDetail(applicationId, appDefinitionId) {
    this.isAppDetailLoading = true;
    try {
      const detail = await getAppDetail({
        applicationId: applicationId,
        appDefinitionId: appDefinitionId
      });
      if (detail && detail.objects) {
        detail.objects = detail.objects.map((o) => ({
          ...o,
          typeBadgeClass: o.isCustom ? "badge-custom" : "badge-standard",
          typeBadgeLabel: o.isCustom ? "Custom Object" : "Standard Object",
          usedInTabsFormatted: (o.usedInTabs || []).join(", ")
        }));
      }
      if (detail && detail.tabs) {
        detail.tabs = detail.tabs.map((t) => ({
          ...t,
          typeBadgeClass: t.isCustom ? "badge-custom" : "badge-standard",
          typeBadgeLabel: t.isCustom ? "Custom Tab" : "Standard Tab"
        }));
      }
      this.selectedAppDetail = detail;
    } catch (err) {
      console.error("Error loading app detail", err);
      this.showToast(
        "Error Loading App Detail",
        this.extractErrorMessage(err),
        "error"
      );
    } finally {
      this.isAppDetailLoading = false;
    }
  }

  handleBackToAppsList() {
    this.selectedApp = null;
    this.selectedAppDetail = null;
    this.appTabSearchTerm = "";
    this.appObjectSearchTerm = "";
    this.appProfileSearchTerm = "";
    this.activeObjectFields = null;
    this.showObjectFieldsModal = false;
  }

  handleAppDetailSubTab(event) {
    this.selectedAppTab = event.currentTarget.dataset.tab;
  }

  get isAppTabsSubTab() {
    return this.selectedAppTab === "tabs";
  }

  get isAppObjectsSubTab() {
    return this.selectedAppTab === "objects";
  }

  get isAppProfilesSubTab() {
    return this.selectedAppTab === "profiles";
  }

  get appTabsTabClass() {
    return this.selectedAppTab === "tabs"
      ? "slds-tabs_default__item slds-is-active"
      : "slds-tabs_default__item";
  }

  get appObjectsTabClass() {
    return this.selectedAppTab === "objects"
      ? "slds-tabs_default__item slds-is-active"
      : "slds-tabs_default__item";
  }

  get appProfilesTabClass() {
    return this.selectedAppTab === "profiles"
      ? "slds-tabs_default__item slds-is-active"
      : "slds-tabs_default__item";
  }

  get appDetailTabsCount() {
    return this.selectedAppDetail && this.selectedAppDetail.tabs
      ? this.selectedAppDetail.tabs.length
      : 0;
  }

  get appDetailObjectsCount() {
    return this.selectedAppDetail && this.selectedAppDetail.objects
      ? this.selectedAppDetail.objects.length
      : 0;
  }

  get selectedAppDetailProfilesCount() {
    return this.selectedAppDetail && this.selectedAppDetail.profiles
      ? this.selectedAppDetail.profiles.length
      : 0;
  }

  handleAppTabSearch(event) {
    this.appTabSearchTerm = event.target.value;
  }

  get filteredAppTabs() {
    if (!this.selectedAppDetail || !this.selectedAppDetail.tabs) return [];
    if (!this.appTabSearchTerm || this.appTabSearchTerm.trim() === "") {
      return this.selectedAppDetail.tabs;
    }
    const term = this.appTabSearchTerm.toLowerCase().trim();
    return this.selectedAppDetail.tabs.filter((t) => {
      const label = (t.tabLabel || "").toLowerCase();
      const name = (t.tabName || "").toLowerCase();
      const sObj = (t.sobjectLabel || "").toLowerCase();
      const sObjName = (t.sobjectName || "").toLowerCase();
      return (
        label.includes(term) ||
        name.includes(term) ||
        sObj.includes(term) ||
        sObjName.includes(term)
      );
    });
  }

  get isFilteredTabsEmpty() {
    return !this.filteredAppTabs || this.filteredAppTabs.length === 0;
  }

  handleAppObjectSearch(event) {
    this.appObjectSearchTerm = event.target.value;
  }

  get filteredAppObjects() {
    if (!this.selectedAppDetail || !this.selectedAppDetail.objects) return [];
    if (!this.appObjectSearchTerm || this.appObjectSearchTerm.trim() === "") {
      return this.selectedAppDetail.objects;
    }
    const term = this.appObjectSearchTerm.toLowerCase().trim();
    return this.selectedAppDetail.objects.filter((o) => {
      const label = (o.label || "").toLowerCase();
      const name = (o.apiName || "").toLowerCase();
      return label.includes(term) || name.includes(term);
    });
  }

  get isFilteredObjectsEmpty() {
    return !this.filteredAppObjects || this.filteredAppObjects.length === 0;
  }

  get appProfileFilterOptions() {
    return [
      { label: "All Profiles", value: "All" },
      { label: "Assigned (Access Granted)", value: "Assigned" },
      { label: "Unassigned (No Access)", value: "Unassigned" },
      { label: "License Restricted", value: "Restricted" }
    ];
  }

  handleAppProfileSearch(event) {
    this.appProfileSearchTerm = event.target.value;
  }

  handleAppProfileFilter(event) {
    this.appProfileFilter = event.detail.value;
  }

  get filteredAppProfiles() {
    if (!this.selectedAppDetail || !this.selectedAppDetail.profiles) return [];
    const isAppCustom = this.selectedAppDetail.app && this.selectedAppDetail.app.isCustom;
    return this.selectedAppDetail.profiles
      .map((p) => {
        const isGuest = p.userLicenseName && (
          p.userLicenseName.toLowerCase().includes("guest") ||
          p.userLicenseName.toLowerCase().includes("chatter free")
        );
        const isRestricted = p.isRestricted || (!p.hasAccess && !isAppCustom && isGuest);
        const restrictionReason = p.restrictionReason || (isRestricted
          ? `${p.userLicenseName} profiles cannot access standard Salesforce applications.`
          : "");
        return {
          ...p,
          isRestricted,
          restrictionReason
        };
      })
      .filter((p) => {
        if (this.appProfileFilter === "Assigned" && !p.hasAccess) return false;
        if (this.appProfileFilter === "Unassigned" && (p.hasAccess || p.isRestricted)) return false;
        if (this.appProfileFilter === "Restricted" && !p.isRestricted) return false;

        if (this.appProfileSearchTerm && this.appProfileSearchTerm.trim() !== "") {
          const term = this.appProfileSearchTerm.toLowerCase().trim();
          const name = (p.profileName || "").toLowerCase();
          const license = (p.userLicenseName || "").toLowerCase();
          return name.includes(term) || license.includes(term);
        }
        return true;
      });
  }

  get isFilteredProfilesEmpty() {
    return !this.filteredAppProfiles || this.filteredAppProfiles.length === 0;
  }

  async handleToggleAppProfileAccess(event) {
    const profileId = event.currentTarget.dataset.profileId;
    const isChecked = event.target.checked;
    const profile = (this.selectedAppDetail.profiles || []).find(
      (p) => p.profileId === profileId
    );
    if (!profile) return;

    if (isChecked && profile.isRestricted) {
      event.target.checked = false;
      this.showToast(
        "Assignment Restricted",
        profile.restrictionReason || "This profile cannot be assigned to standard applications due to Salesforce license limits.",
        "warning"
      );
      return;
    }

    const appId =
      (this.selectedAppDetail.app &&
        this.selectedAppDetail.app.applicationId) ||
      this.selectedApp.applicationId;
    this.isLoading = true;

    try {
      let result;
      if (isChecked) {
        result = await assignProfileToApp({
          applicationId: appId,
          profileId: profileId
        });
      } else {
        result = await removeProfileFromApp({
          applicationId: appId,
          profileId: profileId
        });
      }

      if (result.success) {
        profile.hasAccess = isChecked;
        const currentCount =
          this.selectedAppDetail.totalProfilesWithAccess || 0;
        const newCount = isChecked
          ? currentCount + 1
          : Math.max(0, currentCount - 1);
        this.selectedAppDetail.totalProfilesWithAccess = newCount;
        if (this.selectedAppDetail.app) {
          this.selectedAppDetail.app.profilesCount = newCount;
        }
        const appInAll = (this.allAppsList || []).find(
          (a) => a.id === this.selectedApp.id || a.applicationId === appId
        );
        if (appInAll) {
          appInAll.profilesCount = newCount;
        }
        const appInList = (this.appsList || []).find(
          (a) => a.id === this.selectedApp.id || a.applicationId === appId
        );
        if (appInList) {
          appInList.profilesCount = newCount;
        }
        this.selectedAppDetail = { ...this.selectedAppDetail };
        this.showToast(
          isChecked ? "Profile Assigned" : "Access Removed",
          result.message ||
            (isChecked
              ? `Granted access to ${profile.profileName}`
              : `Removed access for ${profile.profileName}`),
          "success"
        );
      } else {
        event.target.checked = !isChecked;
        this.showToast("Assignment Not Allowed", result.message, "error");
      }
    } catch (err) {
      event.target.checked = !isChecked;
      console.error("Error updating profile app access", err);
      this.showToast("Error", this.extractErrorMessage(err), "error");
    } finally {
      this.isLoading = false;
    }
  }

  async handleViewObjectFields(event) {
    const objApiName = event.currentTarget.dataset.object;
    const objLabel = event.currentTarget.dataset.label || objApiName;
    this.activeObjectForFields = { apiName: objApiName, label: objLabel };
    this.showObjectFieldsModal = true;
    this.isLoadingObjectFields = true;
    this.objectFieldSearchTerm = "";
    try {
      const fields = await getAppObjectFields({ sobjectType: objApiName });
      this.activeObjectFields = (fields || []).map((f) => ({
        ...f,
        typeBadgeClass: f.isCustom ? "badge-custom" : "badge-standard",
        typeBadgeLabel: f.isCustom ? "Custom" : "Standard"
      }));
    } catch (err) {
      console.error("Error loading object fields", err);
      this.showToast("Error", this.extractErrorMessage(err), "error");
      this.activeObjectFields = [];
    } finally {
      this.isLoadingObjectFields = false;
    }
  }

  handleCloseObjectFieldsModal() {
    this.showObjectFieldsModal = false;
    this.activeObjectForFields = null;
    this.activeObjectFields = null;
    this.objectFieldSearchTerm = "";
  }

  handleObjectFieldSearch(event) {
    this.objectFieldSearchTerm = event.target.value;
  }

  get filteredObjectFields() {
    if (!this.activeObjectFields) return [];
    if (
      !this.objectFieldSearchTerm ||
      this.objectFieldSearchTerm.trim() === ""
    ) {
      return this.activeObjectFields;
    }
    const term = this.objectFieldSearchTerm.toLowerCase().trim();
    return this.activeObjectFields.filter(
      (f) =>
        (f.label && f.label.toLowerCase().includes(term)) ||
        (f.apiName && f.apiName.toLowerCase().includes(term)) ||
        (f.dataType && f.dataType.toLowerCase().includes(term))
    );
  }

  get isFilteredObjectFieldsEmpty() {
    return !this.filteredObjectFields || this.filteredObjectFields.length === 0;
  }

  async loadUserOptions() {
    try {
      const res = await getUserOptions();
      this.allUserOptions = res || [];
      this.updateTargetDropdowns();
    } catch (err) {
      console.error("Error loading user options", err);
    }
  }

  get objProfileBtnVariant() {
    return this.objTargetType === "Profile" ? "brand" : "neutral";
  }

  get objUserBtnVariant() {
    return this.objTargetType === "User" ? "brand" : "neutral";
  }

  get objPermSetBtnVariant() {
    return this.objTargetType === "PermissionSet" ? "brand" : "neutral";
  }

  get flsProfileBtnVariant() {
    return this.flsTargetType === "Profile" ? "brand" : "neutral";
  }

  get flsUserBtnVariant() {
    return this.flsTargetType === "User" ? "brand" : "neutral";
  }

  get flsPermSetBtnVariant() {
    return this.flsTargetType === "PermissionSet" ? "brand" : "neutral";
  }

  get objTargetLabel() {
    if (this.objTargetType === "User") return "Select User";
    if (this.objTargetType === "PermissionSet") return "Select Permission Set";
    return "Select Profile";
  }

  get flsTargetLabel() {
    if (this.flsTargetType === "User") return "Select User";
    if (this.flsTargetType === "PermissionSet") return "Select Permission Set";
    return "Select Profile";
  }

  get objTargetPlaceholder() {
    if (this.objTargetType === "User") return "Select User...";
    if (this.objTargetType === "PermissionSet") return "Select Permission Set...";
    return "Select Profile...";
  }

  get flsTargetPlaceholder() {
    if (this.flsTargetType === "User") return "Select User...";
    if (this.flsTargetType === "PermissionSet") return "Select Permission Set...";
    return "Select Profile...";
  }

  updateTargetDropdowns() {
    if (this.objTargetType === "PermissionSet") {
      this.objTargetOptions = this.permSetOptionsAll.map((ps) => ({
        label: `${ps.label} (${ps.isCustom ? "Custom" : "Standard"})`,
        value: ps.id
      }));
    } else if (this.objTargetType === "User") {
      this.objTargetOptions = this.allUserOptions.map((u) => ({
        label: `${u.name} (${u.licenseName})`,
        value: u.id
      }));
    } else {
      this.objTargetOptions = this.profilesList.map((p) => {
        const lic =
          p.userLicenseName &&
          p.userLicenseName !== "None" &&
          p.userLicenseName !== p.name
            ? ` (${p.userLicenseName})`
            : "";
        return {
          label: `${p.name}${lic}`,
          value: p.id
        };
      });
    }
    if (
      this.objTargetOptions.length > 0 &&
      !this.objTargetOptions.some((o) => o.value === this.objSelectedTargetId)
    ) {
      this.objSelectedTargetId = this.objTargetOptions[0].value;
    }

    if (this.flsTargetType === "PermissionSet") {
      this.flsTargetOptions = this.permSetOptionsAll.map((ps) => ({
        label: `${ps.label} (${ps.isCustom ? "Custom" : "Standard"})`,
        value: ps.id
      }));
    } else if (this.flsTargetType === "User") {
      this.flsTargetOptions = this.allUserOptions.map((u) => ({
        label: `${u.name} (${u.licenseName})`,
        value: u.id
      }));
    } else {
      this.flsTargetOptions = this.profilesList.map((p) => {
        const lic =
          p.userLicenseName &&
          p.userLicenseName !== "None" &&
          p.userLicenseName !== p.name
            ? ` (${p.userLicenseName})`
            : "";
        return {
          label: `${p.name}${lic}`,
          value: p.id
        };
      });
    }
    if (
      this.flsTargetOptions.length > 0 &&
      !this.flsTargetOptions.some((o) => o.value === this.flsSelectedTargetId)
    ) {
      this.flsSelectedTargetId = this.flsTargetOptions[0].value;
    }
  }

  handleObjViewByProfile() {
    if (this.objTargetType === "Profile") return;
    this.objTargetType = "Profile";
    this.objSelectedTargetId = "";
    this.updateTargetDropdowns();
    this.fetchObjectPermissions();
  }

  handleObjViewByUser() {
    if (this.objTargetType === "User") return;
    this.objTargetType = "User";
    this.objSelectedTargetId = "";
    this.updateTargetDropdowns();
    this.fetchObjectPermissions();
  }

  handleObjViewByPermSet() {
    if (this.objTargetType === "PermissionSet") return;
    this.objTargetType = "PermissionSet";
    this.objSelectedTargetId = "";
    this.updateTargetDropdowns();
    this.fetchObjectPermissions();
  }

  handleFlsViewByProfile() {
    if (this.flsTargetType === "Profile") return;
    this.flsTargetType = "Profile";
    this.flsSelectedTargetId = "";
    this.updateTargetDropdowns();
    this.fetchFieldPermissions();
  }

  handleFlsViewByUser() {
    if (this.flsTargetType === "User") return;
    this.flsTargetType = "User";
    this.flsSelectedTargetId = "";
    this.updateTargetDropdowns();
    this.fetchFieldPermissions();
  }

  handleFlsViewByPermSet() {
    if (this.flsTargetType === "PermissionSet") return;
    this.flsTargetType = "PermissionSet";
    this.flsSelectedTargetId = "";
    this.updateTargetDropdowns();
    this.fetchFieldPermissions();
  }

  async handleTabChange(event) {
    const tabName = event.detail.name || event.detail.value;
    if (!tabName) return;
    await this.resetAndLoadTab(tabName);
  }

  async resetAndLoadTab(tabName, subTab) {
    this.activeTab = tabName;

    // Reset modals & dialogs across tabs
    this.showConfirmModal = false;
    this.showAssignModal = false;
    this.showProfileModal = false;
    this.showEditObjectModal = false;
    this.showEditFieldModal = false;
    this.showCreatePsModal = false;
    this.showCreatePsgModal = false;
    this.showCreateUserModal = false;

    switch (tabName) {
      case "userAndProfile":
      case "profiles":
      case "users":
        this.activeTab = "userAndProfile";
        this.userProfileSubTab = subTab || "profile";
        this.selectedUser = null;
        this.selectedProfile = null;
        this.userSearchTerm = "";
        this.userProfileFilter = "";
        this.userStatusFilter = "All";
        this.profileSearchTerm = "";
        this.profileTypeFilter = "All";
        this.pages = { ...this.pages, users: 1 };
        this.isLoading = true;
        try {
          await Promise.all([this.loadProfiles(), this.loadUsers(true)]);
        } catch (error) {
          this.showToast("Error", this.extractErrorMessage(error), "error");
        } finally {
          this.isLoading = false;
        }
        break;

      case "permSets":
        this.selectedPermSet = null;
        this.selectedPermSetSubTab = "users";
        this.editingPermSetId = null;
        this.psSearchTerm = "";
        this.psTypeFilter = "Custom";
        this.pages = { ...this.pages, permSets: 1 };
        this.isLoading = true;
        try {
          await this.loadPermissionSets(true);
        } catch (error) {
          this.showToast("Error", this.extractErrorMessage(error), "error");
        } finally {
          this.isLoading = false;
        }
        break;

      case "groups":
        this.selectedGroup = null;
        this.selectedGroupSubTab = "permSets";
        this.psgSearchTerm = "";
        this.psgStatusFilter = "All";
        this.psgTypeFilter = "Custom";
        this.isLoading = true;
        try {
          await this.loadGroups();
        } catch (error) {
          this.showToast("Error", this.extractErrorMessage(error), "error");
        } finally {
          this.isLoading = false;
        }
        break;

      case "objects":
        this.objSearchTerm = "";
        this.pages = { ...this.pages, objects: 1 };
        this.updateTargetDropdowns();
        if (this.objSelectedTargetId) {
          await this.fetchObjectPermissions(true);
        }
        break;

      case "fields":
        this.flsSearchTerm = "";
        this.pages = { ...this.pages, fls: 1 };
        this.updateTargetDropdowns();
        if (this.flsSelectedTargetId) {
          await this.fetchFieldPermissions(true);
        }
        break;

      case "apps":
        this.appSearchTerm = "";
        this.isLoading = true;
        try {
          await this.loadApps();
        } catch (error) {
          this.showToast("Error", this.extractErrorMessage(error), "error");
        } finally {
          this.isLoading = false;
        }
        break;

      default:
        break;
    }
  }

  async handleSubTabToggle(event) {
    const subtab = event.currentTarget.dataset.subtab;
    if (subtab) {
      this.userProfileSubTab = subtab;
      this.selectedProfile = null;
      this.selectedUser = null;
      if (subtab === "profile") {
        this.profileSearchTerm = "";
        this.isLoading = true;
        try {
          await this.loadProfiles();
        } finally {
          this.isLoading = false;
        }
      } else {
        this.userSearchTerm = "";
        this.isLoading = true;
        try {
          await this.loadUsers(true);
        } finally {
          this.isLoading = false;
        }
      }
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
        detail.assignedPermissionSets = (
          detail.assignedPermissionSets || []
        ).map((ps) => ({
          ...ps,
          typeClass: ps.isCustom ? "badge-custom" : "badge-standard"
        }));
      }
      this.selectedUser = detail;
    } catch (error) {
      this.showToast("Error", this.extractErrorMessage(error), "error");
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
    const actionText = newStatus ? "activate" : "deactivate";
    this.confirmTitle = `Confirm User Account Action`;
    this.confirmMessage = `Are you sure you want to ${actionText} the user account for ${this.selectedUser.user.name}?`;
    this.confirmItemName = this.selectedUser.user.name;
    this.confirmTargetName = actionText;
    this.confirmActionType = "toggleUserStatus";
    this.confirmPayload = {
      userId: this.selectedUser.user.userId,
      isActive: newStatus
    };
    this.showConfirmModal = true;
  }

  // ---- Create User ----

  handleNewUserClick() {
    this.newUser = {
      firstName: "",
      lastName: "",
      email: "",
      username: "",
      alias: "",
      profileId: ""
    };
    this.showCreateUserModal = true;
  }

  handleCloseCreateUserModal() {
    this.showCreateUserModal = false;
  }

  handleNewUserFieldChange(event) {
    const field = event.target.dataset.field;
    const value = event.detail ? event.detail.value : event.target.value;
    this.newUser = { ...this.newUser, [field]: value };
  }

  get createUserSaveDisabled() {
    const u = this.newUser;
    return (
      !u.lastName ||
      !u.lastName.trim() ||
      !u.email ||
      !u.email.trim() ||
      !u.profileId
    );
  }

  async handleCreateUser() {
    this.showCreateUserModal = false;
    this.isLoading = true;
    try {
      const res = await createUser({
        firstName: this.newUser.firstName,
        lastName: this.newUser.lastName,
        email: this.newUser.email,
        username: this.newUser.username,
        alias: this.newUser.alias,
        profileId: this.newUser.profileId
      });
      this.showToast("User created", res.message, "success");
      await Promise.all([this.loadUsers(), this.loadOverview()]);
      // Open the new user's detail view so their access can be configured.
      await this.viewUserDetailById(res.recordId);
    } catch (error) {
      this.showToast(
        "Could not create user",
        this.extractErrorMessage(error),
        "error"
      );
    } finally {
      this.isLoading = false;
    }
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
        detail.assignedUsers = (detail.assignedUsers || []).map((u) => ({
          ...u,
          statusClass: u.isActive ? "badge-active" : "badge-inactive"
        }));
      }
      this.selectedPermSet = detail;
    } catch (error) {
      this.showToast("Error", this.extractErrorMessage(error), "error");
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

  // ---- Create Permission Set + full access editor ----

  handleNewPermSetClick() {
    this.pendingEditorTab = "objects";
    this.openCreatePsModal();
  }

  async openCreatePsModal() {
    this.newPs = { label: "", apiName: "", licenseId: "", description: "" };
    if (this.licenseOptions.length === 0) {
      try {
        this.licenseOptions = await getUserLicenseOptions();
      } catch (error) {
        this.showToast("Error", this.extractErrorMessage(error), "error");
      }
    }
    this.showCreatePsModal = true;
  }

  handleCloseCreatePsModal() {
    this.showCreatePsModal = false;
  }

  handleNewPsFieldChange(event) {
    const field = event.target.dataset.field;
    const value = event.detail ? event.detail.value : event.target.value;
    this.newPs = { ...this.newPs, [field]: value };
  }

  get createPsSaveDisabled() {
    return !this.newPs.label || !this.newPs.label.trim();
  }

  async handleCreatePermSet() {
    this.showCreatePsModal = false;
    this.isLoading = true;
    try {
      const res = await createPermissionSet({
        label: this.newPs.label,
        apiName: this.newPs.apiName,
        licenseId: this.newPs.licenseId || null,
        description: this.newPs.description
      });
      this.showToast("Permission set created", res.message, "success");
      await this.loadPermissionSets();
      // Open the full editor on the new set, focused on the chosen category.
      this.openPermSetEditor(
        res.recordId,
        this.newPs.label.trim(),
        this.pendingEditorTab
      );
    } catch (error) {
      this.showToast(
        "Could not create permission set",
        this.extractErrorMessage(error),
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  openPermSetEditor(id, label, initialTab) {
    this.selectedPermSet = null;
    this.editingPermSetId = id;
    this.editingPermSetLabel = label;
    this.editingPermSetInitialTab = initialTab || "objects";
  }

  handleOpenPermSetEditor(event) {
    this.openPermSetEditor(
      event.currentTarget.dataset.id,
      event.currentTarget.dataset.label,
      event.currentTarget.dataset.tab || "objects"
    );
  }

  handleClosePermSetEditor() {
    this.editingPermSetId = null;
    this.editingPermSetLabel = "";
    this.loadPermissionSets();
  }

  get isEditingPermSet() {
    return Boolean(this.editingPermSetId);
  }

  handlePromptAssignUsersToPs() {
    this.assignModalTitle = `Assign Users to ${this.selectedPermSet.permissionSet.label}`;
    this.assignModalType = "assignUsersToPs";
    this.assignSearchTerm = "";
    this.assignItems = (this.selectedPermSet.availableUsers || []).map((u) => ({
      id: u.userId,
      title: u.name,
      subtitle: `${u.username} • Profile: ${u.profileName}`,
      selected: false,
      rowClass: "selectable-row"
    }));
    this.selectedAssignIds = [];
    this.showAssignModal = true;
  }

  handlePromptRemoveUserFromPs(event) {
    const userId = event.currentTarget.dataset.id;
    const userName = event.currentTarget.dataset.name;
    this.confirmTitle = "Confirm User Removal";
    this.confirmMessage = `Are you sure you want to remove ${userName} from permission set "${this.selectedPermSet.permissionSet.label}"?`;
    this.confirmItemName = userName;
    this.confirmTargetName = this.selectedPermSet.permissionSet.label;
    this.confirmActionType = "removeUserFromPs";
    this.confirmPayload = {
      permSetId: this.selectedPermSet.permissionSet.id,
      userId
    };
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
        detail.includedPermissionSets = (
          detail.includedPermissionSets || []
        ).map((ps) => ({
          ...ps,
          typeClass: ps.isCustom ? "badge-custom" : "badge-standard"
        }));
        detail.assignedUsers = (detail.assignedUsers || []).map((u) => ({
          ...u,
          statusClass: u.isActive ? "badge-active" : "badge-inactive"
        }));
      }
      this.selectedGroup = detail;
    } catch (error) {
      this.showToast("Error", this.extractErrorMessage(error), "error");
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
    this.assignModalType = "assignUsersToGroup";
    this.assignSearchTerm = "";
    this.assignItems = (this.selectedGroup.availableUsers || []).map((u) => ({
      id: u.userId,
      title: u.name,
      subtitle: `${u.username} • Profile: ${u.profileName}`,
      selected: false,
      rowClass: "selectable-row"
    }));
    this.selectedAssignIds = [];
    this.showAssignModal = true;
  }

  handlePromptRemoveUserFromGroup(event) {
    const userId = event.currentTarget.dataset.id;
    const userName = event.currentTarget.dataset.name;
    this.confirmTitle = "Confirm Group User Removal";
    this.confirmMessage = `Are you sure you want to remove ${userName} from group "${this.selectedGroup.groupSummary.masterLabel}"?`;
    this.confirmItemName = userName;
    this.confirmTargetName = this.selectedGroup.groupSummary.masterLabel;
    this.confirmActionType = "removeUserFromGroup";
    this.confirmPayload = {
      groupId: this.selectedGroup.groupSummary.id,
      userId
    };
    this.showConfirmModal = true;
  }

  // ---- Create Permission Set Group + component management ----

  handleNewPsgClick() {
    this.newPsg = { masterLabel: "", developerName: "", description: "" };
    this.showCreatePsgModal = true;
  }

  handleCloseCreatePsgModal() {
    this.showCreatePsgModal = false;
  }

  handleNewPsgFieldChange(event) {
    const field = event.target.dataset.field;
    const value = event.detail ? event.detail.value : event.target.value;
    this.newPsg = { ...this.newPsg, [field]: value };
  }

  get createPsgSaveDisabled() {
    return !this.newPsg.masterLabel || !this.newPsg.masterLabel.trim();
  }

  async handleCreatePermSetGroup() {
    this.showCreatePsgModal = false;
    this.isLoading = true;
    try {
      const res = await createPermissionSetGroup({
        masterLabel: this.newPsg.masterLabel,
        developerName: this.newPsg.developerName,
        description: this.newPsg.description
      });
      this.showToast("Permission set group created", res.message, "success");
      await this.loadGroups();
      // Open the new group's detail view so components and users can be added.
      await this.viewGroupDetailById(res.recordId);
    } catch (error) {
      this.showToast(
        "Could not create group",
        this.extractErrorMessage(error),
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  handlePromptAddPermSetsToGroup() {
    this.assignModalTitle = `Add Permission Sets to ${this.selectedGroup.groupSummary.masterLabel}`;
    this.assignModalType = "addPermSetsToGroup";
    this.assignSearchTerm = "";
    this.assignItems = (this.selectedGroup.availablePermissionSets || []).map(
      (ps) => ({
        id: ps.id,
        title: ps.label,
        subtitle: `${ps.name} • License: ${ps.licenseName}`,
        selected: false,
        rowClass: "selectable-row"
      })
    );
    this.selectedAssignIds = [];
    this.showAssignModal = true;
  }

  handlePromptRemovePermSetFromGroup(event) {
    const permSetId = event.currentTarget.dataset.id;
    const permSetName = event.currentTarget.dataset.name;
    this.confirmTitle = "Remove Permission Set from Group";
    this.confirmMessage = `Remove "${permSetName}" from group "${this.selectedGroup.groupSummary.masterLabel}"? Users of the group lose the access it provides.`;
    this.confirmItemName = permSetName;
    this.confirmTargetName = this.selectedGroup.groupSummary.masterLabel;
    this.confirmActionType = "removePermSetFromGroup";
    this.confirmPayload = {
      groupId: this.selectedGroup.groupSummary.id,
      permSetId
    };
    this.showConfirmModal = true;
  }

  // =========================================================================
  // SECTION 4: PROFILES
  // =========================================================================
  handleProfileSearch(event) {
    this.profileSearchTerm = event.target.value;
    this.loadProfiles();
  }

  handleProfileTypeFilterChange(event) {
    this.profileTypeFilter = event.detail.value;
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
        detail.associatedUsers = (detail.associatedUsers || []).map((u) => ({
          ...u,
          statusClass: u.isActive ? "badge-active" : "badge-inactive"
        }));
        detail.systemPermissions = (detail.systemPermissions || []).map(
          (sp) => ({
            ...sp,
            statusClass: sp.isEnabled ? "badge-active" : "badge-inactive",
            statusLabel: sp.isEnabled ? "Enabled" : "Disabled"
          })
        );
      }
      this.selectedProfile = detail;
    } catch (error) {
      this.showToast("Error", this.extractErrorMessage(error), "error");
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
    this.objSelectedTargetId = "";
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

  async fetchObjectPermissions(resetPage = true) {
    if (!this.objSelectedTargetId) return;
    if (resetPage) {
      this.pages = { ...this.pages, objects: 1 };
    }
    this.isLoading = true;
    try {
      const res = await getObjectPermissionsForTarget({
        parentId: this.objSelectedTargetId,
        targetType: this.objTargetType,
        searchTerm: this.objSearchTerm,
        pageNumber: this.pages.objects,
        pageSize: PAGE_SIZE
      });
      this.objPermItems = ((res && res.records) || []).map((op) => ({
        ...op,
        typeClass: op.isCustomObject ? "badge-custom" : "badge-standard",
        typeBadge: op.isCustomObject ? "Custom" : "Standard"
      }));
      this.totals = { ...this.totals, objects: res ? res.totalCount : 0 };
    } catch (error) {
      this.showToast("Error", this.extractErrorMessage(error), "error");
    } finally {
      this.isLoading = false;
    }
  }

  handleOpenEditObject(event) {
    const objType = event.currentTarget.dataset.type;
    const item = this.objPermItems.find((o) => o.sobjectType === objType);
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
    if (
      event.target.checked &&
      (field === "permissionsCreate" ||
        field === "permissionsEdit" ||
        field === "permissionsDelete" ||
        field === "permissionsViewAllRecords" ||
        field === "permissionsModifyAllRecords")
    ) {
      this.editObjectData.permissionsRead = true;
    }
    if (event.target.checked && field === "permissionsModifyAllRecords") {
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
      this.showToast("Success", res.message, "success");
      this.showEditObjectModal = false;
      await this.fetchObjectPermissions();
    } catch (error) {
      this.showToast("Save Failed", this.extractErrorMessage(error), "error");
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
    this.flsSelectedTargetId = "";
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

  async fetchFieldPermissions(resetPage = true) {
    if (!this.flsSelectedTargetId || !this.flsSelectedObject) return;
    if (resetPage) {
      this.pages = { ...this.pages, fls: 1 };
    }
    this.isLoading = true;
    try {
      const res = await getFieldPermissionsForTarget({
        parentId: this.flsSelectedTargetId,
        targetType: this.flsTargetType,
        sobjectType: this.flsSelectedObject,
        searchTerm: this.flsSearchTerm,
        pageNumber: this.pages.fls,
        pageSize: PAGE_SIZE
      });
      this.flsFieldItems = ((res && res.records) || []).map((fp) => ({
        ...fp,
        typeClass: fp.isCustom ? "badge-custom" : "badge-standard",
        typeBadge: fp.isCustom ? "Custom" : "Standard"
      }));
      this.totals = { ...this.totals, fls: res ? res.totalCount : 0 };
    } catch (error) {
      this.showToast("Error", this.extractErrorMessage(error), "error");
    } finally {
      this.isLoading = false;
    }
  }

  handleOpenEditField(event) {
    const fieldName = event.currentTarget.dataset.field;
    const item = this.flsFieldItems.find((f) => f.field === fieldName);
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
    if (event.target.checked && field === "permissionsEdit") {
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
      this.showToast("Success", res.message, "success");
      this.showEditFieldModal = false;
      await this.fetchFieldPermissions();
    } catch (error) {
      this.showToast("Save Failed", this.extractErrorMessage(error), "error");
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
        case "toggleUserStatus":
          res = await toggleUserActiveStatus({
            userId: this.confirmPayload.userId,
            isActive: this.confirmPayload.isActive
          });
          this.showToast("Success", res.message, "success");
          await this.viewUserDetailById(this.confirmPayload.userId);
          break;

        case "removeUserFromPs":
          res = await removePermissionSetFromUser({
            userId: this.confirmPayload.userId,
            permissionSetId: this.confirmPayload.permSetId
          });
          this.showToast("Success", res.message, "success");
          await this.viewPermSetDetailById(this.confirmPayload.permSetId);
          break;

        case "removeUserFromGroup":
          res = await removePermissionSetGroupFromUser({
            userId: this.confirmPayload.userId,
            permissionSetGroupId: this.confirmPayload.groupId
          });
          this.showToast("Success", res.message, "success");
          await this.viewGroupDetailById(this.confirmPayload.groupId);
          break;

        case "removePermSetFromGroup":
          res = await removePermissionSetFromGroup({
            groupId: this.confirmPayload.groupId,
            permissionSetId: this.confirmPayload.permSetId
          });
          this.showToast("Success", res.message, "success");
          await this.viewGroupDetailById(this.confirmPayload.groupId);
          break;

        default:
          break;
      }
    } catch (error) {
      this.showToast("Action Failed", this.extractErrorMessage(error), "error");
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
    this.assignItems = this.assignItems.map((item) => {
      if (item.id === itemId) {
        const newSelected = !item.selected;
        return {
          ...item,
          selected: newSelected,
          rowClass: newSelected ? "selectable-row selected" : "selectable-row"
        };
      }
      return item;
    });

    const selected = this.assignItems
      .filter((i) => i.selected)
      .map((i) => i.id);
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
    return this.assignItems.filter(
      (i) =>
        (i.title && i.title.toLowerCase().includes(this.assignSearchTerm)) ||
        (i.subtitle && i.subtitle.toLowerCase().includes(this.assignSearchTerm))
    );
  }

  async handleExecuteAssignAction() {
    if (this.selectedAssignIds.length === 0) {
      this.showToast(
        "Selection Required",
        "Please select at least one item to assign.",
        "warning"
      );
      return;
    }

    this.isLoading = true;
    this.showAssignModal = false;

    try {
      let res;
      switch (this.assignModalType) {
        case "assignUsersToPs":
          res = await assignUsersToPermissionSet({
            permissionSetId: this.selectedPermSet.permissionSet.id,
            userIds: this.selectedAssignIds
          });
          this.showToast("Success", res.message, "success");
          await this.viewPermSetDetailById(
            this.selectedPermSet.permissionSet.id
          );
          break;

        case "assignUsersToGroup":
          res = await assignUsersToPermissionSetGroup({
            permissionSetGroupId: this.selectedGroup.groupSummary.id,
            userIds: this.selectedAssignIds
          });
          this.showToast("Success", res.message, "success");
          await this.viewGroupDetailById(this.selectedGroup.groupSummary.id);
          break;

        case "addPermSetsToGroup":
          res = await addPermissionSetsToGroup({
            groupId: this.selectedGroup.groupSummary.id,
            permissionSetIds: this.selectedAssignIds
          });
          this.showToast("Success", res.message, "success");
          await this.viewGroupDetailById(this.selectedGroup.groupSummary.id);
          break;

        default:
          break;
      }
    } catch (error) {
      this.showToast(
        "Assignment Error",
        this.extractErrorMessage(error),
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  // =========================================================================
  // COMPUTED GETTERS
  // =========================================================================
  get navItems() {
    return [
      {
        name: "userAndProfile",
        value: "userAndProfile",
        label: "User & Profile",
        icon: "utility:user_role"
      },
      {
        name: "permSets",
        value: "permSets",
        label: "Permission Sets",
        icon: "utility:lock"
      },
      {
        name: "groups",
        value: "groups",
        label: "Permission Set Groups",
        icon: "utility:groups"
      },
      {
        name: "apps",
        value: "apps",
        label: "Apps",
        icon: "utility:apps"
      },
      {
        name: "objects",
        value: "objects",
        label: "Object Access",
        icon: "utility:database"
      },
      {
        name: "fields",
        value: "fields",
        label: "Field-Level Security",
        icon: "utility:shield"
      }
    ];
  }

  get isUserAndProfileTab() {
    return (
      this.activeTab === "userAndProfile" ||
      this.activeTab === "profiles" ||
      this.activeTab === "users"
    );
  }

  get isProfileSubActive() {
    return this.userProfileSubTab === "profile";
  }

  get isUserSubActive() {
    return this.userProfileSubTab === "user";
  }

  get profileSubTabClass() {
    return this.isProfileSubActive
      ? "subnav-toggle-btn subnav-toggle-btn_active"
      : "subnav-toggle-btn";
  }

  get userSubTabClass() {
    return this.isUserSubActive
      ? "subnav-toggle-btn subnav-toggle-btn_active"
      : "subnav-toggle-btn";
  }

  get profileIconVariant() {
    return this.isProfileSubActive ? "inverse" : "";
  }

  get userIconVariant() {
    return this.isUserSubActive ? "inverse" : "";
  }

  get profileCountBadgeClass() {
    return this.isProfileSubActive
      ? "subnav-toggle-badge subnav-toggle-badge_active"
      : "subnav-toggle-badge";
  }

  get userCountBadgeClass() {
    return this.isUserSubActive
      ? "subnav-toggle-badge subnav-toggle-badge_active"
      : "subnav-toggle-badge";
  }

  get showSubNavToggle() {
    return true;
  }

  get activeSubTabLabel() {
    return this.isProfileSubActive ? "Profiles" : "Users";
  }

  get isUsersTab() {
    return this.isUserAndProfileTab && this.isUserSubActive;
  }

  get isPermSetsTab() {
    return this.activeTab === "permSets";
  }

  get isGroupsTab() {
    return this.activeTab === "groups";
  }

  get isProfilesTab() {
    return this.isUserAndProfileTab && this.isProfileSubActive;
  }

  get isObjectsTab() {
    return this.activeTab === "objects";
  }

  get isFieldsTab() {
    return this.activeTab === "fields";
  }

  get isAppsTab() {
    return this.activeTab === "apps";
  }

  get isObjTargetCustom() {
    return this.objTargetType === "PermissionSet";
  }

  get isFlsTargetCustom() {
    return this.flsTargetType === "PermissionSet";
  }

  get assignSaveDisabled() {
    return !this.selectedAssignIds || this.selectedAssignIds.length === 0;
  }

  get selectedUserBadgeClass() {
    return this.selectedUser &&
      this.selectedUser.user &&
      this.selectedUser.user.isActive
      ? "slds-badge slds-theme_success"
      : "slds-badge";
  }

  get toggleUserBtnLabel() {
    if (!this.selectedUser || !this.selectedUser.user) return "Activate";
    return this.selectedUser.user.isActive
      ? "Deactivate User"
      : "Activate User";
  }

  get toggleUserBtnIcon() {
    if (!this.selectedUser || !this.selectedUser.user) return "utility:check";
    return this.selectedUser.user.isActive ? "utility:ban" : "utility:check";
  }

  get selectedPermSetTypeClass() {
    if (!this.selectedPermSet || !this.selectedPermSet.permissionSet)
      return "badge-standard";
    return this.selectedPermSet.permissionSet.isCustom
      ? "badge-custom"
      : "badge-standard";
  }

  get selectedPermSetEditableClass() {
    if (!this.selectedPermSet || !this.selectedPermSet.permissionSet)
      return "badge-metadata";
    return this.selectedPermSet.permissionSet.isEditable
      ? "badge-editable"
      : "badge-metadata";
  }

  get selectedPermSetEditableLabel() {
    if (!this.selectedPermSet || !this.selectedPermSet.permissionSet)
      return "View Only (Metadata Managed)";
    return this.selectedPermSet.permissionSet.isEditable
      ? "Editable"
      : "View Only (Metadata Managed)";
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

  get hasGroupIncludedSets() {
    return Boolean(this.selectedGroup?.includedPermissionSets?.length);
  }

  get hasObjPermItems() {
    return Boolean(this.objPermItems?.length);
  }

  get hasFlsFieldItems() {
    return Boolean(this.flsFieldItems?.length);
  }

  // =========================================================================
  // SERVER-SIDE PAGINATION (15 rows per page, numbered controls)
  // =========================================================================
  buildPageView(rows, listKey) {
    const total = this.totals[listKey] || 0;
    const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
    const current = Math.min(Math.max(this.pages[listKey] || 1, 1), totalPages);
    const startIdx = total === 0 ? 0 : (current - 1) * PAGE_SIZE;
    const count = rows ? rows.length : 0;
    return {
      rows: rows || [],
      page: current,
      totalPages,
      total,
      showing: total === 0 ? "0" : `${startIdx + 1}–${startIdx + count}`,
      prevDisabled: current <= 1,
      nextDisabled: current >= totalPages,
      multiPage: totalPages > 1,
      items: this.buildPageItems(current, totalPages, listKey)
    };
  }

  // Numbered page buttons with ellipsis, e.g. 1 2 … 11
  buildPageItems(current, totalPages, listKey) {
    const items = [];
    const add = (n) =>
      items.push({
        key: `${listKey}-p${n}`,
        page: String(n),
        label: String(n),
        isEllipsis: false,
        cssClass: n === current ? "page-num page-num_active" : "page-num"
      });
    const addGap = (key) =>
      items.push({ key: `${listKey}-${key}`, isEllipsis: true, label: "…" });

    if (totalPages <= 7) {
      for (let n = 1; n <= totalPages; n++) add(n);
      return items;
    }

    add(1);
    let start = Math.max(2, current - 1);
    let end = Math.min(totalPages - 1, current + 1);
    if (current <= 3) {
      start = 2;
      end = 4;
    }
    if (current >= totalPages - 2) {
      start = totalPages - 3;
      end = totalPages - 1;
    }
    if (start > 2) addGap("gap1");
    for (let n = start; n <= end; n++) add(n);
    if (end < totalPages - 1) addGap("gap2");
    add(totalPages);
    return items;
  }

  get usersView() {
    return this.buildPageView(this.usersList, "users");
  }

  get permSetsView() {
    return this.buildPageView(this.permSetsList, "permSets");
  }

  get objPermView() {
    return this.buildPageView(this.objPermItems, "objects");
  }

  get flsFieldView() {
    return this.buildPageView(this.flsFieldItems, "fls");
  }

  async handlePageChange(event) {
    const ds = event.currentTarget.dataset;
    const listKey = ds.list;
    let target;
    if (ds.page) {
      target = parseInt(ds.page, 10);
    } else {
      target = (this.pages[listKey] || 1) + (ds.dir === "next" ? 1 : -1);
    }
    if (!target || target < 1 || target === this.pages[listKey]) {
      return;
    }
    this.pages = { ...this.pages, [listKey]: target };
    switch (listKey) {
      case "users":
        await this.loadUsers(false);
        break;
      case "permSets":
        await this.loadPermissionSets(false);
        break;
      case "objects":
        await this.fetchObjectPermissions(false);
        break;
      case "fls":
        await this.fetchFieldPermissions(false);
        break;
      default:
        break;
    }
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
      {
        key: "stat-profiles",
        tab: "userAndProfile",
        subTab: "profile",
        label: "Profiles",
        value: o.totalProfiles,
        meta: "Baseline access",
        title: "Open Profiles"
      },
      {
        key: "stat-users",
        tab: "userAndProfile",
        subTab: "user",
        label: "Users",
        value: o.totalUsers,
        meta: `${o.activeUsers} active`,
        title: "Open Users"
      },
      {
        key: "stat-permSets",
        tab: "permSets",
        label: "Permission Sets",
        value: o.totalPermSets,
        meta: `${o.customPermSets} custom`,
        title: "Open Permission Sets"
      },
      {
        key: "stat-groups",
        tab: "groups",
        label: "Permission Set Groups",
        value: o.totalPermSetGroups,
        meta: "Bundled access",
        title: "Open Permission Set Groups"
      },
      {
        key: "stat-apps",
        tab: "apps",
        label: "Apps",
        value: o.totalApps,
        meta: "Lightning and connected",
        title: "Open App Security"
      }
    ];
  }

  async handleStatClick(event) {
    const tab = event.currentTarget.dataset.tab;
    const subTab = event.currentTarget.dataset.subtab;
    await this.resetAndLoadTab(tab, subTab);
  }

  navigateToUrl(url) {
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url }
    });
  }

  handleOpenSetupHome() {
    this.navigateToUrl("/lightning/setup/SetupOneHome/home");
  }

  handleOpenUserSetup() {
    const userId = this.selectedUser.user.userId;
    this.navigateToUrl(
      `/lightning/setup/ManageUsers/page?address=%2F${userId}%3Fnoredirect%3D1`
    );
  }

  handleOpenProfileSetup() {
    this.navigateToUrl(
      `/lightning/setup/EnhancedProfiles/page?address=%2F${this.selectedProfile.profile.id}`
    );
  }

  async handleOpenUserProfile() {
    const profileId = this.selectedUser.user.profileId;
    this.activeTab = "userAndProfile";
    this.userProfileSubTab = "profile";
    await this.viewProfileDetailById(profileId);
  }

  async handleEditorOpenUser(event) {
    this.activeTab = "userAndProfile";
    this.userProfileSubTab = "user";
    await this.viewUserDetailById(event.detail.userId);
  }

  handleEditorAccessChange() {
    // Keep list counts and header stats current without blocking the editor
    Promise.all([
      this.loadOverview(),
      this.loadUsers(),
      this.loadPermissionSets()
    ]).catch(() => {});
  }

  get assignableProfileOptions() {
    return this.profileOptions.filter((o) => o.value);
  }

  get profileSaveDisabled() {
    return (
      !this.newProfileId ||
      (this.selectedUser &&
        this.newProfileId === this.selectedUser.user.profileId)
    );
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
      const res = await changeUserProfile({
        userId,
        profileId: this.newProfileId
      });
      this.showToast("Profile updated", res.message, "success");
      await this.viewUserDetailById(userId);
      this.handleEditorAccessChange();
    } catch (error) {
      this.showToast(
        "Profile not changed",
        this.extractErrorMessage(error),
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  extractErrorMessage(error) {
    if (!error) return "Unknown error occurred.";
    let msg = "";
    if (error.body && error.body.message) {
      msg = error.body.message;
    } else if (error.message) {
      msg = error.message;
    } else {
      msg = JSON.stringify(error);
    }

    if (msg.includes("TABSET_LIMIT_EXCEEDED")) {
      return "This profile cannot be assigned to this application because its license does not permit access to standard Salesforce applications (license limit: 0 standard apps).";
    }

    if (msg.includes("first error:")) {
      let sub = msg.substring(msg.indexOf("first error:") + 12).trim();
      const commaIdx = sub.indexOf(",");
      if (commaIdx !== -1 && commaIdx < 40) {
        sub = sub.substring(commaIdx + 1).trim();
      }
      if (sub.endsWith(": []")) {
        sub = sub.substring(0, sub.length - 4).trim();
      } else if (sub.endsWith("[]")) {
        sub = sub.substring(0, sub.length - 2).trim();
      }
      if (sub) return sub;
    }

    return msg;
  }
}