/**
 * @description Service layer handling queries, security checks, and DML operations
 * for the Salesforce Admin Access Console.
 */
public with sharing class AdminSecurityService {
  /**
   * @description Verify whether current user has administrative rights to view/modify security
   */
  public static void verifyAdminAccess() {
    if (!isCurrentUserAdmin()) {
      throw new AuraHandledException(
        'Unauthorized: You do not have sufficient administrative privileges to access the Admin Security Console.'
      );
    }
  }

  /**
   * @description Check admin status safely using user permissions and schema checks
   */
  public static Boolean isCurrentUserAdmin() {
    // Check permission to assign permission sets or manage users
    Boolean canAssign =
      Schema.sObjectType.PermissionSetAssignment.isCreateable() &&
      Schema.sObjectType.PermissionSetAssignment.isDeletable();
    if (canAssign) {
      return true;
    }

    // Profile check
    List<User> users = [
      SELECT
        Id,
        Profile.PermissionsModifyAllData,
        Profile.PermissionsManageUsers
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];

    if (!users.isEmpty()) {
      User u = users[0];
      if (
        u.Profile.PermissionsModifyAllData || u.Profile.PermissionsManageUsers
      ) {
        return true;
      }
    }
    return false;
  }

  /**
   * @description High-level statistics for the Admin Access header
   */
  public static AdminSecurityDataModel.AdminSecurityOverview getAdminOverview() {
    verifyAdminAccess();

    AdminSecurityDataModel.AdminSecurityOverview overview = new AdminSecurityDataModel.AdminSecurityOverview();
    overview.totalUsers = [SELECT COUNT() FROM User];
    overview.activeUsers = [SELECT COUNT() FROM User WHERE IsActive = TRUE];
    overview.totalPermSets = [
      SELECT COUNT()
      FROM PermissionSet
      WHERE IsOwnedByProfile = FALSE
    ];
    overview.customPermSets = [
      SELECT COUNT()
      FROM PermissionSet
      WHERE IsOwnedByProfile = FALSE AND IsCustom = TRUE
    ];
    overview.totalPermSetGroups = [SELECT COUNT() FROM PermissionSetGroup];
    overview.totalProfiles = [SELECT COUNT() FROM Profile];
    overview.totalApps = [
      SELECT COUNT()
      FROM AppMenuItem
      WHERE Type = 'TabSet' OR Type = 'ConnectedApplication'
    ];
    overview.currentAdminName = UserInfo.getName();

    List<User> curUser = [
      SELECT Profile.Name
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    overview.currentAdminProfile = (!curUser.isEmpty() &&
      curUser[0].Profile != null)
      ? curUser[0].Profile.Name
      : 'Administrator';
    overview.isAuthorizedAdmin = true;

    return overview;
  }

  /**
   * @description Retrieve user list with optional search and profile filter
   */
  public static AdminSecurityDataModel.UserPage getUsers(
    String searchTerm,
    String profileId,
    String statusFilter,
    Integer pageNumber,
    Integer pageSize
  ) {
    verifyAdminAccess();

    String query = 'SELECT Id, Name, Username, Email, IsActive, ProfileId, Profile.Name, UserRoleId, UserRole.Name, SmallPhotoUrl, CreatedDate, LastLoginDate FROM User';
    List<String> conditions = new List<String>();
    String term = '';

    if (String.isNotBlank(profileId)) {
      conditions.add('ProfileId = :profileId');
    }

    if (statusFilter == 'Active') {
      conditions.add('IsActive = true');
    } else if (statusFilter == 'Inactive') {
      conditions.add('IsActive = false');
    }

    if (String.isNotBlank(searchTerm)) {
      term = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
      conditions.add(
        '(Name LIKE :term OR Username LIKE :term OR Email LIKE :term)'
      );
    }

    String whereClause = conditions.isEmpty()
      ? ''
      : (' WHERE ' + String.join(conditions, ' AND '));
    Integer safeSize = (pageSize == null || pageSize <= 0) ? 15 : pageSize;
    Integer safePage = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
    Integer offset = (safePage - 1) * safeSize;
    Integer totalCount = Database.countQuery(
      'SELECT count() FROM User' + whereClause
    );

    query += whereClause + ' ORDER BY Name ASC LIMIT :safeSize OFFSET :offset';

    List<User> userRecords = Database.query(query);
    Set<Id> userIds = new Set<Id>();
    for (User u : userRecords) {
      userIds.add(u.Id);
    }

    // Query assignments to compute counts
    Map<Id, Integer> permSetCountMap = new Map<Id, Integer>();
    Map<Id, Integer> permSetGroupCountMap = new Map<Id, Integer>();

    if (!userIds.isEmpty()) {
      List<PermissionSetAssignment> assignments = [
        SELECT
          AssigneeId,
          PermissionSetId,
          PermissionSetGroupId,
          PermissionSet.IsOwnedByProfile
        FROM PermissionSetAssignment
        WHERE AssigneeId IN :userIds
      ];

      for (PermissionSetAssignment psa : assignments) {
        if (psa.PermissionSetGroupId != null) {
          Integer count = permSetGroupCountMap.containsKey(psa.AssigneeId)
            ? permSetGroupCountMap.get(psa.AssigneeId)
            : 0;
          permSetGroupCountMap.put(psa.AssigneeId, count + 1);
        } else if (
          psa.PermissionSetId != null && !psa.PermissionSet.IsOwnedByProfile
        ) {
          Integer count = permSetCountMap.containsKey(psa.AssigneeId)
            ? permSetCountMap.get(psa.AssigneeId)
            : 0;
          permSetCountMap.put(psa.AssigneeId, count + 1);
        }
      }
    }

    List<AdminSecurityDataModel.AdminUserInfo> results = new List<AdminSecurityDataModel.AdminUserInfo>();
    for (User u : userRecords) {
      AdminSecurityDataModel.AdminUserInfo dto = new AdminSecurityDataModel.AdminUserInfo();
      dto.userId = u.Id;
      dto.name = u.Name;
      dto.username = u.Username;
      dto.email = u.Email;
      dto.profileId = u.ProfileId;
      dto.profileName = u.Profile != null ? u.Profile.Name : '-';
      dto.roleId = u.UserRoleId;
      dto.roleName = u.UserRole != null ? u.UserRole.Name : '-';
      dto.isActive = u.IsActive;
      dto.statusBadge = u.IsActive ? 'Active' : 'Inactive';
      dto.smallPhotoUrl = u.SmallPhotoUrl;
      dto.permSetCount = permSetCountMap.containsKey(u.Id)
        ? permSetCountMap.get(u.Id)
        : 0;
      dto.permSetGroupCount = permSetGroupCountMap.containsKey(u.Id)
        ? permSetGroupCountMap.get(u.Id)
        : 0;
      dto.createdDateFormatted = u.CreatedDate != null
        ? u.CreatedDate.format('yyyy-MM-dd')
        : '-';
      dto.lastLoginFormatted = u.LastLoginDate != null
        ? u.LastLoginDate.format('yyyy-MM-dd HH:mm')
        : 'Never';
      results.add(dto);
    }

    results.sort();

    AdminSecurityDataModel.UserPage page = new AdminSecurityDataModel.UserPage();
    page.records = results;
    page.totalCount = totalCount;
    return page;
  }

  public static List<Map<String, String>> getUserOptions() {
    verifyAdminAccess();
    List<Map<String, String>> options = new List<Map<String, String>>();
    for (User u : [
      SELECT Id, Name, ProfileId, Profile.Name, Profile.UserLicense.Name
      FROM User
      WHERE IsActive = TRUE
      ORDER BY Name ASC
      LIMIT 500
    ]) {
      Map<String, String> item = new Map<String, String>();
      item.put('id', u.Id);
      item.put('name', u.Name);
      item.put('profileId', u.ProfileId != null ? String.valueOf(u.ProfileId) : '');
      item.put('profileName', u.Profile != null ? u.Profile.Name : '');
      item.put(
        'licenseName',
        u.Profile != null && u.Profile.UserLicense != null
          ? u.Profile.UserLicense.Name
          : (u.Profile != null ? u.Profile.Name : 'Standard')
      );
      options.add(item);
    }
    return options;
  }

  /**
   * @description Fetch detailed user security profile: direct perm sets, groups, and effective object access
   */
  public static AdminSecurityDataModel.UserDetailView getUserDetail(Id userId) {
    verifyAdminAccess();

    if (userId == null) {
      throw new AuraHandledException('User ID cannot be blank.');
    }

    User u = [
      SELECT
        Id,
        Name,
        Username,
        Email,
        IsActive,
        ProfileId,
        Profile.Name,
        UserRoleId,
        UserRole.Name,
        SmallPhotoUrl,
        CreatedDate,
        LastLoginDate
      FROM User
      WHERE Id = :userId
      LIMIT 1
    ];

    AdminSecurityDataModel.AdminUserInfo userDto = new AdminSecurityDataModel.AdminUserInfo();
    userDto.userId = u.Id;
    userDto.name = u.Name;
    userDto.username = u.Username;
    userDto.email = u.Email;
    userDto.profileId = u.ProfileId;
    userDto.profileName = u.Profile != null ? u.Profile.Name : '-';
    userDto.roleId = u.UserRoleId;
    userDto.roleName = u.UserRole != null ? u.UserRole.Name : '-';
    userDto.isActive = u.IsActive;
    userDto.statusBadge = u.IsActive ? 'Active' : 'Inactive';
    userDto.smallPhotoUrl = u.SmallPhotoUrl;
    userDto.createdDateFormatted = u.CreatedDate != null
      ? u.CreatedDate.format('yyyy-MM-dd')
      : '-';
    userDto.lastLoginFormatted = u.LastLoginDate != null
      ? u.LastLoginDate.format('yyyy-MM-dd HH:mm')
      : 'Never';

    // 1. Direct Permission Sets
    List<PermissionSetAssignment> psaList = [
      SELECT
        Id,
        PermissionSetId,
        PermissionSet.Name,
        PermissionSet.Label,
        PermissionSet.Description,
        PermissionSet.License.Name,
        PermissionSet.IsCustom,
        PermissionSet.IsOwnedByProfile,
        PermissionSetGroupId,
        PermissionSetGroup.DeveloperName,
        PermissionSetGroup.MasterLabel,
        PermissionSetGroup.Description,
        PermissionSetGroup.Status,
        PermissionSetGroup.NamespacePrefix
      FROM PermissionSetAssignment
      WHERE AssigneeId = :userId
    ];

    Set<Id> assignedPermSetIds = new Set<Id>();
    Set<Id> assignedGroupIds = new Set<Id>();
    List<AdminSecurityDataModel.PermissionSetSummary> assignedPermSets = new List<AdminSecurityDataModel.PermissionSetSummary>();
    List<AdminSecurityDataModel.PermissionSetGroupSummary> assignedGroups = new List<AdminSecurityDataModel.PermissionSetGroupSummary>();

    for (PermissionSetAssignment psa : psaList) {
      if (psa.PermissionSetGroupId != null) {
        assignedGroupIds.add(psa.PermissionSetGroupId);
        AdminSecurityDataModel.PermissionSetGroupSummary grp = new AdminSecurityDataModel.PermissionSetGroupSummary();
        grp.id = psa.PermissionSetGroupId;
        grp.developerName = psa.PermissionSetGroup.DeveloperName;
        grp.masterLabel = psa.PermissionSetGroup.MasterLabel;
        grp.description = psa.PermissionSetGroup.Description;
        grp.status = psa.PermissionSetGroup.Status;
        grp.isCustom = (psa.PermissionSetGroup.NamespacePrefix == null);
        assignedGroups.add(grp);
      } else if (
        psa.PermissionSetId != null && !psa.PermissionSet.IsOwnedByProfile
      ) {
        assignedPermSetIds.add(psa.PermissionSetId);
        AdminSecurityDataModel.PermissionSetSummary ps = new AdminSecurityDataModel.PermissionSetSummary();
        ps.id = psa.PermissionSetId;
        ps.name = psa.PermissionSet.Name;
        ps.label = psa.PermissionSet.Label;
        ps.description = psa.PermissionSet.Description;
        ps.licenseName = psa.PermissionSet.License != null
          ? psa.PermissionSet.License.Name
          : 'None';
        ps.isCustom = psa.PermissionSet.IsCustom;
        ps.typeBadge = psa.PermissionSet.IsCustom ? 'Custom' : 'Standard';
        assignedPermSets.add(ps);
      }
    }

    // 2. Available Permission Sets
    List<PermissionSet> availPsList = [
      SELECT Id, Name, Label, Description, License.Name, IsCustom
      FROM PermissionSet
      WHERE IsOwnedByProfile = FALSE AND Id NOT IN :assignedPermSetIds
      ORDER BY Label ASC
      LIMIT 150
    ];

    List<AdminSecurityDataModel.PermissionSetSummary> availablePermSets = new List<AdminSecurityDataModel.PermissionSetSummary>();
    for (PermissionSet ps : availPsList) {
      AdminSecurityDataModel.PermissionSetSummary psDto = new AdminSecurityDataModel.PermissionSetSummary();
      psDto.id = ps.Id;
      psDto.name = ps.Name;
      psDto.label = ps.Label;
      psDto.description = ps.Description;
      psDto.licenseName = ps.License != null ? ps.License.Name : 'None';
      psDto.isCustom = ps.IsCustom;
      psDto.typeBadge = ps.IsCustom ? 'Custom' : 'Standard';
      availablePermSets.add(psDto);
    }

    // 3. Available Permission Set Groups
    List<PermissionSetGroup> availGrpList = [
      SELECT Id, DeveloperName, MasterLabel, Description, Status, NamespacePrefix
      FROM PermissionSetGroup
      WHERE Id NOT IN :assignedGroupIds
      ORDER BY MasterLabel ASC
      LIMIT 100
    ];

    List<AdminSecurityDataModel.PermissionSetGroupSummary> availableGroups = new List<AdminSecurityDataModel.PermissionSetGroupSummary>();
    for (PermissionSetGroup grp : availGrpList) {
      AdminSecurityDataModel.PermissionSetGroupSummary grpDto = new AdminSecurityDataModel.PermissionSetGroupSummary();
      grpDto.id = grp.Id;
      grpDto.developerName = grp.DeveloperName;
      grpDto.masterLabel = grp.MasterLabel;
      grpDto.description = grp.Description;
      grpDto.status = grp.Status;
      grpDto.isCustom = (grp.NamespacePrefix == null);
      availableGroups.add(grpDto);
    }

    // 4. Effective Object Access calculation
    // Profile permission set Id
    Id profilePermSetId = null;
    if (u.ProfileId != null) {
      List<PermissionSet> pList = [
        SELECT Id
        FROM PermissionSet
        WHERE ProfileId = :u.ProfileId
        LIMIT 1
      ];
      if (!pList.isEmpty()) {
        profilePermSetId = pList[0].Id;
      }
    }

    Set<Id> allSourcePermSetIds = new Set<Id>();
    if (profilePermSetId != null)
      allSourcePermSetIds.add(profilePermSetId);
    allSourcePermSetIds.addAll(assignedPermSetIds);

    if (!assignedGroupIds.isEmpty()) {
      List<PermissionSetGroupComponent> components = [
        SELECT PermissionSetId
        FROM PermissionSetGroupComponent
        WHERE PermissionSetGroupId IN :assignedGroupIds
      ];
      for (PermissionSetGroupComponent comp : components) {
        allSourcePermSetIds.add(comp.PermissionSetId);
      }
    }

    List<AdminSecurityDataModel.ObjectPermItem> effectivePerms = new List<AdminSecurityDataModel.ObjectPermItem>();
    if (!allSourcePermSetIds.isEmpty()) {
      List<ObjectPermissions> opList = [
        SELECT
          Id,
          ParentId,
          Parent.Name,
          Parent.Label,
          Parent.IsOwnedByProfile,
          SobjectType,
          PermissionsRead,
          PermissionsCreate,
          PermissionsEdit,
          PermissionsDelete,
          PermissionsViewAllRecords,
          PermissionsModifyAllRecords
        FROM ObjectPermissions
        WHERE ParentId IN :allSourcePermSetIds
        ORDER BY SobjectType ASC
        LIMIT 500
      ];

      Map<String, AdminSecurityDataModel.ObjectPermItem> objMap = new Map<String, AdminSecurityDataModel.ObjectPermItem>();
      Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

      for (ObjectPermissions op : opList) {
        String objKey = op.SobjectType;
        AdminSecurityDataModel.ObjectPermItem item;

        if (!objMap.containsKey(objKey)) {
          item = new AdminSecurityDataModel.ObjectPermItem();
          item.sobjectType = op.SobjectType;
          item.isCustomObject = op.SobjectType.endsWith('__c');
          if (globalDescribe.containsKey(op.SobjectType.toLowerCase())) {
            item.sobjectLabel = globalDescribe.get(op.SobjectType.toLowerCase())
              .getDescribe()
              .getLabel();
          } else {
            item.sobjectLabel = op.SobjectType;
          }
          item.permissionsRead = false;
          item.permissionsCreate = false;
          item.permissionsEdit = false;
          item.permissionsDelete = false;
          item.permissionsViewAllRecords = false;
          item.permissionsModifyAllRecords = false;
          item.source = '';
          objMap.put(objKey, item);
        } else {
          item = objMap.get(objKey);
        }

        // Aggregate boolean OR
        if (op.PermissionsRead)
          item.permissionsRead = true;
        if (op.PermissionsCreate)
          item.permissionsCreate = true;
        if (op.PermissionsEdit)
          item.permissionsEdit = true;
        if (op.PermissionsDelete)
          item.permissionsDelete = true;
        if (op.PermissionsViewAllRecords)
          item.permissionsViewAllRecords = true;
        if (op.PermissionsModifyAllRecords)
          item.permissionsModifyAllRecords = true;

        String srcName = op.Parent.IsOwnedByProfile
          ? 'Profile (' + u.Profile.Name + ')'
          : op.Parent.Label;
        if (!item.source.contains(srcName)) {
          item.source += (String.isBlank(item.source) ? '' : ', ') + srcName;
        }
      }
      effectivePerms = objMap.values();
      effectivePerms.sort();
    }

    userDto.permSetCount = assignedPermSets.size();
    userDto.permSetGroupCount = assignedGroups.size();

    AdminSecurityDataModel.UserDetailView detail = new AdminSecurityDataModel.UserDetailView();
    detail.user = userDto;
    detail.assignedPermissionSets = assignedPermSets;
    detail.availablePermissionSets = availablePermSets;
    detail.assignedPermissionSetGroups = assignedGroups;
    detail.availablePermissionSetGroups = availableGroups;
    detail.effectiveObjectPermissions = effectivePerms;

    return detail;
  }

  /**
   * @description Fetch all standalone permission sets with search and filters
   */
  public static AdminSecurityDataModel.PermissionSetPage getPermissionSets(
    String searchTerm,
    String typeFilter,
    Integer pageNumber,
    Integer pageSize
  ) {
    verifyAdminAccess();

    String filters = ' WHERE IsOwnedByProfile = false';
    String term = '';

    if (typeFilter == 'Custom') {
      filters += ' AND IsCustom = true';
    } else if (typeFilter == 'Standard') {
      filters += ' AND IsCustom = false';
    }

    if (String.isNotBlank(searchTerm)) {
      term = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
      filters += ' AND (Name LIKE :term OR Label LIKE :term OR Description LIKE :term)';
    }

    Integer safeSize = (pageSize == null || pageSize <= 0) ? 15 : pageSize;
    Integer safePage = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
    Integer offset = (safePage - 1) * safeSize;
    Integer totalCount = Database.countQuery(
      'SELECT count() FROM PermissionSet' + filters
    );

    String query =
      'SELECT Id, Name, Label, Description, License.Name, IsCustom, CreatedDate FROM PermissionSet' +
      filters +
      ' ORDER BY Label ASC LIMIT :safeSize OFFSET :offset';

    List<PermissionSet> psList = Database.query(query);
    Set<Id> psIds = new Set<Id>();
    for (PermissionSet ps : psList) {
      psIds.add(ps.Id);
    }

    // Count assigned users
    Map<Id, Integer> userCountMap = new Map<Id, Integer>();
    if (!psIds.isEmpty()) {
      List<AggregateResult> aggResults = [
        SELECT PermissionSetId, COUNT(Id) cnt
        FROM PermissionSetAssignment
        WHERE PermissionSetId IN :psIds AND PermissionSetGroupId = NULL
        GROUP BY PermissionSetId
      ];
      for (AggregateResult ar : aggResults) {
        userCountMap.put(
          (Id) ar.get('PermissionSetId'),
          (Integer) ar.get('cnt')
        );
      }
    }

    List<AdminSecurityDataModel.PermissionSetSummary> results = new List<AdminSecurityDataModel.PermissionSetSummary>();
    for (PermissionSet ps : psList) {
      AdminSecurityDataModel.PermissionSetSummary dto = new AdminSecurityDataModel.PermissionSetSummary();
      dto.id = ps.Id;
      dto.name = ps.Name;
      dto.label = ps.Label;
      dto.description = ps.Description;
      dto.licenseName = ps.License != null ? ps.License.Name : 'None';
      dto.isCustom = ps.IsCustom;
      dto.typeBadge = ps.IsCustom ? 'Custom' : 'Standard';
      dto.userCount = userCountMap.containsKey(ps.Id)
        ? userCountMap.get(ps.Id)
        : 0;
      dto.createdDateFormatted = ps.CreatedDate != null
        ? ps.CreatedDate.format('yyyy-MM-dd')
        : '-';
      dto.isEditable = ps.IsCustom;
      results.add(dto);
    }

    results.sort();

    AdminSecurityDataModel.PermissionSetPage page = new AdminSecurityDataModel.PermissionSetPage();
    page.records = results;
    page.totalCount = totalCount;
    return page;
  }

  /**
   * @description Fetch details of a permission set including assigned users, object perms, and field perms
   */
  public static AdminSecurityDataModel.PermissionSetDetail getPermissionSetDetail(
    Id permissionSetId
  ) {
    verifyAdminAccess();

    if (permissionSetId == null) {
      throw new AuraHandledException('Permission Set ID cannot be blank.');
    }

    PermissionSet ps = [
      SELECT
        Id,
        Name,
        Label,
        Description,
        License.Name,
        IsCustom,
        IsOwnedByProfile,
        CreatedDate
      FROM PermissionSet
      WHERE Id = :permissionSetId
      LIMIT 1
    ];

    AdminSecurityDataModel.PermissionSetSummary summary = new AdminSecurityDataModel.PermissionSetSummary();
    summary.id = ps.Id;
    summary.name = ps.Name;
    summary.label = ps.Label;
    summary.description = ps.Description;
    summary.licenseName = ps.License != null ? ps.License.Name : 'None';
    summary.isCustom = ps.IsCustom;
    summary.typeBadge = ps.IsCustom ? 'Custom' : 'Standard';
    summary.createdDateFormatted = ps.CreatedDate != null
      ? ps.CreatedDate.format('yyyy-MM-dd')
      : '-';
    summary.isEditable = (ps.IsCustom && !ps.IsOwnedByProfile);

    // Assigned users
    List<PermissionSetAssignment> psaList = [
      SELECT
        AssigneeId,
        Assignee.Name,
        Assignee.Username,
        Assignee.Email,
        Assignee.IsActive,
        Assignee.Profile.Name
      FROM PermissionSetAssignment
      WHERE PermissionSetId = :permissionSetId AND PermissionSetGroupId = NULL
      ORDER BY Assignee.Name ASC
      LIMIT 200
    ];

    Set<Id> assignedUserIds = new Set<Id>();
    List<AdminSecurityDataModel.AdminUserInfo> assignedUsers = new List<AdminSecurityDataModel.AdminUserInfo>();
    for (PermissionSetAssignment psa : psaList) {
      assignedUserIds.add(psa.AssigneeId);
      AdminSecurityDataModel.AdminUserInfo uDto = new AdminSecurityDataModel.AdminUserInfo();
      uDto.userId = psa.AssigneeId;
      uDto.name = psa.Assignee.Name;
      uDto.username = psa.Assignee.Username;
      uDto.email = psa.Assignee.Email;
      uDto.isActive = psa.Assignee.IsActive;
      uDto.statusBadge = psa.Assignee.IsActive ? 'Active' : 'Inactive';
      uDto.profileName = psa.Assignee.Profile != null
        ? psa.Assignee.Profile.Name
        : '-';
      assignedUsers.add(uDto);
    }

    summary.userCount = assignedUsers.size();

    // Available users for quick assignment
    List<User> availUsers = [
      SELECT Id, Name, Username, Email, IsActive, Profile.Name
      FROM User
      WHERE IsActive = TRUE AND Id NOT IN :assignedUserIds
      ORDER BY Name ASC
      LIMIT 100
    ];

    List<AdminSecurityDataModel.AdminUserInfo> availableUsers = new List<AdminSecurityDataModel.AdminUserInfo>();
    for (User u : availUsers) {
      AdminSecurityDataModel.AdminUserInfo uDto = new AdminSecurityDataModel.AdminUserInfo();
      uDto.userId = u.Id;
      uDto.name = u.Name;
      uDto.username = u.Username;
      uDto.email = u.Email;
      uDto.isActive = u.IsActive;
      uDto.profileName = u.Profile != null ? u.Profile.Name : '-';
      availableUsers.add(uDto);
    }

    // Object Permissions
    List<ObjectPermissions> opList = [
      SELECT
        Id,
        ParentId,
        SobjectType,
        PermissionsRead,
        PermissionsCreate,
        PermissionsEdit,
        PermissionsDelete,
        PermissionsViewAllRecords,
        PermissionsModifyAllRecords
      FROM ObjectPermissions
      WHERE ParentId = :permissionSetId
      ORDER BY SobjectType ASC
      LIMIT 200
    ];

    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    List<AdminSecurityDataModel.ObjectPermItem> objectPerms = new List<AdminSecurityDataModel.ObjectPermItem>();

    for (ObjectPermissions op : opList) {
      AdminSecurityDataModel.ObjectPermItem item = new AdminSecurityDataModel.ObjectPermItem();
      item.id = op.Id;
      item.parentId = op.ParentId;
      item.parentName = ps.Label;
      item.parentType = 'PermissionSet';
      item.sobjectType = op.SobjectType;
      item.isCustomObject = op.SobjectType.endsWith('__c');
      if (globalDescribe.containsKey(op.SobjectType.toLowerCase())) {
        item.sobjectLabel = globalDescribe.get(op.SobjectType.toLowerCase())
          .getDescribe()
          .getLabel();
      } else {
        item.sobjectLabel = op.SobjectType;
      }
      item.permissionsRead = op.PermissionsRead;
      item.permissionsCreate = op.PermissionsCreate;
      item.permissionsEdit = op.PermissionsEdit;
      item.permissionsDelete = op.PermissionsDelete;
      item.permissionsViewAllRecords = op.PermissionsViewAllRecords;
      item.permissionsModifyAllRecords = op.PermissionsModifyAllRecords;
      item.isEditable = summary.isEditable;
      objectPerms.add(item);
    }

    // Field Permissions
    List<FieldPermissions> fpList = [
      SELECT Id, ParentId, SobjectType, Field, PermissionsRead, PermissionsEdit
      FROM FieldPermissions
      WHERE ParentId = :permissionSetId
      ORDER BY SobjectType ASC, Field ASC
      LIMIT 200
    ];

    List<AdminSecurityDataModel.FieldPermItem> fieldPerms = new List<AdminSecurityDataModel.FieldPermItem>();
    for (FieldPermissions fp : fpList) {
      AdminSecurityDataModel.FieldPermItem item = new AdminSecurityDataModel.FieldPermItem();
      item.id = fp.Id;
      item.parentId = fp.ParentId;
      item.parentName = ps.Label;
      item.sobjectType = fp.SobjectType;
      item.field = fp.Field;
      item.fieldLabel = fp.Field.substringAfter('.');
      item.permissionsRead = fp.PermissionsRead;
      item.permissionsEdit = fp.PermissionsEdit;
      item.isCustom = fp.Field.endsWith('__c');
      item.isEditable = summary.isEditable;
      fieldPerms.add(item);
    }

    AdminSecurityDataModel.PermissionSetDetail detail = new AdminSecurityDataModel.PermissionSetDetail();
    detail.permissionSet = summary;
    detail.assignedUsers = assignedUsers;
    detail.availableUsers = availableUsers;
    detail.objectPermissions = objectPerms;
    detail.fieldPermissions = fieldPerms;

    return detail;
  }

  /**
   * @description Fetch all Permission Set Groups
   */
  public static List<AdminSecurityDataModel.PermissionSetGroupSummary> getPermissionSetGroups(
    String searchTerm,
    String statusFilter
  ) {
    verifyAdminAccess();

    String query = 'SELECT Id, DeveloperName, MasterLabel, Description, Status, NamespacePrefix FROM PermissionSetGroup';
    List<String> conditions = new List<String>();

    if (String.isNotBlank(statusFilter) && statusFilter != 'All') {
      conditions.add('Status = :statusFilter');
    }

    if (String.isNotBlank(searchTerm)) {
      String term = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
      conditions.add(
        '(DeveloperName LIKE :term OR MasterLabel LIKE :term OR Description LIKE :term)'
      );
    }

    if (!conditions.isEmpty()) {
      query += ' WHERE ' + String.join(conditions, ' AND ');
    }

    query += ' ORDER BY MasterLabel ASC LIMIT 100';

    List<PermissionSetGroup> grpList = Database.query(query);
    Set<Id> grpIds = new Set<Id>();
    for (PermissionSetGroup grp : grpList) {
      grpIds.add(grp.Id);
    }

    // Component counts & names
    Map<Id, Integer> compCountMap = new Map<Id, Integer>();
    Map<Id, List<String>> compNamesMap = new Map<Id, List<String>>();
    if (!grpIds.isEmpty()) {
      List<PermissionSetGroupComponent> components = [
        SELECT PermissionSetGroupId, PermissionSet.Label
        FROM PermissionSetGroupComponent
        WHERE PermissionSetGroupId IN :grpIds
      ];
      for (PermissionSetGroupComponent comp : components) {
        Integer cnt = compCountMap.containsKey(comp.PermissionSetGroupId)
          ? compCountMap.get(comp.PermissionSetGroupId)
          : 0;
        compCountMap.put(comp.PermissionSetGroupId, cnt + 1);

        if (!compNamesMap.containsKey(comp.PermissionSetGroupId)) {
          compNamesMap.put(comp.PermissionSetGroupId, new List<String>());
        }
        compNamesMap.get(comp.PermissionSetGroupId)
          .add(comp.PermissionSet.Label);
      }
    }

    // User assignment counts
    Map<Id, Integer> userCountMap = new Map<Id, Integer>();
    if (!grpIds.isEmpty()) {
      List<AggregateResult> aggResults = [
        SELECT PermissionSetGroupId, COUNT(Id) cnt
        FROM PermissionSetAssignment
        WHERE PermissionSetGroupId IN :grpIds
        GROUP BY PermissionSetGroupId
      ];
      for (AggregateResult ar : aggResults) {
        userCountMap.put(
          (Id) ar.get('PermissionSetGroupId'),
          (Integer) ar.get('cnt')
        );
      }
    }

    List<AdminSecurityDataModel.PermissionSetGroupSummary> results = new List<AdminSecurityDataModel.PermissionSetGroupSummary>();
    for (PermissionSetGroup grp : grpList) {
      AdminSecurityDataModel.PermissionSetGroupSummary dto = new AdminSecurityDataModel.PermissionSetGroupSummary();
      dto.id = grp.Id;
      dto.developerName = grp.DeveloperName;
      dto.masterLabel = grp.MasterLabel;
      dto.description = grp.Description;
      dto.status = grp.Status;
      dto.isCustom = (grp.NamespacePrefix == null);
      dto.componentCount = compCountMap.containsKey(grp.Id)
        ? compCountMap.get(grp.Id)
        : 0;
      dto.assignedUserCount = userCountMap.containsKey(grp.Id)
        ? userCountMap.get(grp.Id)
        : 0;
      dto.includedPermSetNames = compNamesMap.containsKey(grp.Id)
        ? compNamesMap.get(grp.Id)
        : new List<String>();
      results.add(dto);
    }

    results.sort();
    return results;
  }

  /**
   * @description Fetch details of a Permission Set Group (included perm sets and assigned users)
   */
  public static AdminSecurityDataModel.PermissionSetGroupDetail getPermissionSetGroupDetail(
    Id groupId
  ) {
    verifyAdminAccess();

    if (groupId == null) {
      throw new AuraHandledException(
        'Permission Set Group ID cannot be blank.'
      );
    }

    PermissionSetGroup grp = [
      SELECT Id, DeveloperName, MasterLabel, Description, Status
      FROM PermissionSetGroup
      WHERE Id = :groupId
      LIMIT 1
    ];

    AdminSecurityDataModel.PermissionSetGroupSummary summary = new AdminSecurityDataModel.PermissionSetGroupSummary();
    summary.id = grp.Id;
    summary.developerName = grp.DeveloperName;
    summary.masterLabel = grp.MasterLabel;
    summary.description = grp.Description;
    summary.status = grp.Status;

    // Included permission sets
    List<PermissionSetGroupComponent> components = [
      SELECT
        PermissionSetId,
        PermissionSet.Name,
        PermissionSet.Label,
        PermissionSet.Description,
        PermissionSet.License.Name,
        PermissionSet.IsCustom
      FROM PermissionSetGroupComponent
      WHERE PermissionSetGroupId = :groupId
      ORDER BY PermissionSet.Label ASC
    ];

    List<AdminSecurityDataModel.PermissionSetSummary> includedSets = new List<AdminSecurityDataModel.PermissionSetSummary>();
    Set<Id> includedIds = new Set<Id>();
    for (PermissionSetGroupComponent comp : components) {
      includedIds.add(comp.PermissionSetId);
      AdminSecurityDataModel.PermissionSetSummary ps = new AdminSecurityDataModel.PermissionSetSummary();
      ps.id = comp.PermissionSetId;
      ps.name = comp.PermissionSet.Name;
      ps.label = comp.PermissionSet.Label;
      ps.description = comp.PermissionSet.Description;
      ps.licenseName = comp.PermissionSet.License != null
        ? comp.PermissionSet.License.Name
        : 'None';
      ps.isCustom = comp.PermissionSet.IsCustom;
      ps.typeBadge = comp.PermissionSet.IsCustom ? 'Custom' : 'Standard';
      includedSets.add(ps);
    }
    summary.componentCount = includedSets.size();

    // Permission sets that can still be added to the group.
    List<AdminSecurityDataModel.PermissionSetSummary> availableSets = new List<AdminSecurityDataModel.PermissionSetSummary>();
    for (PermissionSet ps : [
      SELECT Id, Name, Label, Description, License.Name, IsCustom
      FROM PermissionSet
      WHERE
        IsOwnedByProfile = FALSE
        AND PermissionSetGroupId = NULL
        AND Id NOT IN :includedIds
      ORDER BY Label ASC
      LIMIT 500
    ]) {
      AdminSecurityDataModel.PermissionSetSummary dto = new AdminSecurityDataModel.PermissionSetSummary();
      dto.id = ps.Id;
      dto.name = ps.Name;
      dto.label = ps.Label;
      dto.description = ps.Description;
      dto.licenseName = ps.License != null ? ps.License.Name : 'None';
      dto.isCustom = ps.IsCustom;
      dto.typeBadge = ps.IsCustom ? 'Custom' : 'Standard';
      availableSets.add(dto);
    }

    // Assigned users
    List<PermissionSetAssignment> psaList = [
      SELECT
        AssigneeId,
        Assignee.Name,
        Assignee.Username,
        Assignee.Email,
        Assignee.IsActive,
        Assignee.Profile.Name
      FROM PermissionSetAssignment
      WHERE PermissionSetGroupId = :groupId
      ORDER BY Assignee.Name ASC
      LIMIT 200
    ];

    Set<Id> assignedUserIds = new Set<Id>();
    List<AdminSecurityDataModel.AdminUserInfo> assignedUsers = new List<AdminSecurityDataModel.AdminUserInfo>();
    for (PermissionSetAssignment psa : psaList) {
      assignedUserIds.add(psa.AssigneeId);
      AdminSecurityDataModel.AdminUserInfo uDto = new AdminSecurityDataModel.AdminUserInfo();
      uDto.userId = psa.AssigneeId;
      uDto.name = psa.Assignee.Name;
      uDto.username = psa.Assignee.Username;
      uDto.email = psa.Assignee.Email;
      uDto.isActive = psa.Assignee.IsActive;
      uDto.statusBadge = psa.Assignee.IsActive ? 'Active' : 'Inactive';
      uDto.profileName = psa.Assignee.Profile != null
        ? psa.Assignee.Profile.Name
        : '-';
      assignedUsers.add(uDto);
    }
    summary.assignedUserCount = assignedUsers.size();

    // Available users for assignment
    List<User> availUsers = [
      SELECT Id, Name, Username, Email, IsActive, Profile.Name
      FROM User
      WHERE IsActive = TRUE AND Id NOT IN :assignedUserIds
      ORDER BY Name ASC
      LIMIT 100
    ];

    List<AdminSecurityDataModel.AdminUserInfo> availableUsers = new List<AdminSecurityDataModel.AdminUserInfo>();
    for (User u : availUsers) {
      AdminSecurityDataModel.AdminUserInfo uDto = new AdminSecurityDataModel.AdminUserInfo();
      uDto.userId = u.Id;
      uDto.name = u.Name;
      uDto.username = u.Username;
      uDto.email = u.Email;
      uDto.isActive = u.IsActive;
      uDto.profileName = u.Profile != null ? u.Profile.Name : '-';
      availableUsers.add(uDto);
    }

    AdminSecurityDataModel.PermissionSetGroupDetail detail = new AdminSecurityDataModel.PermissionSetGroupDetail();
    detail.groupSummary = summary;
    detail.includedPermissionSets = includedSets;
    detail.availablePermissionSets = availableSets;
    detail.assignedUsers = assignedUsers;
    detail.availableUsers = availableUsers;

    return detail;
  }

  /**
   * @description Create a new, empty permission set group. Component permission sets and user
   * assignments are added afterwards from the group detail view.
   */
  public static AdminSecurityDataModel.DmlResult createPermissionSetGroup(
    String masterLabel,
    String developerName,
    String description
  ) {
    verifyAdminAccess();
    if (String.isBlank(masterLabel)) {
      throw new AuraHandledException(
        'A label is required to create a permission set group.'
      );
    }
    String devName = sanitizeDeveloperName(
      String.isBlank(developerName) ? masterLabel : developerName
    );
    if (String.isBlank(devName)) {
      throw new AuraHandledException(
        'Could not derive a valid developer name. Enter one using letters, numbers and underscores.'
      );
    }
    if (
      ![
          SELECT Id
          FROM PermissionSetGroup
          WHERE DeveloperName = :devName
          LIMIT 1
        ]
        .isEmpty()
    ) {
      throw new AuraHandledException(
        'A permission set group with the developer name "' +
          devName +
          '" already exists. Choose another name.'
      );
    }

    PermissionSetGroup grp = new PermissionSetGroup(
      MasterLabel = masterLabel.abbreviate(80),
      DeveloperName = devName,
      Description = String.isBlank(description)
        ? null
        : description.abbreviate(255)
    );
    insert grp;
    return new AdminSecurityDataModel.DmlResult(
      true,
      'Permission set group "' + grp.MasterLabel + '" created.',
      grp.Id
    );
  }

  /**
   * @description Add one or more permission sets as components of a group.
   */
  public static AdminSecurityDataModel.DmlResult addPermissionSetsToGroup(
    Id groupId,
    List<Id> permissionSetIds
  ) {
    verifyAdminAccess();
    if (
      groupId == null ||
      permissionSetIds == null ||
      permissionSetIds.isEmpty()
    ) {
      throw new AuraHandledException(
        'Group ID and at least one permission set are required.'
      );
    }

    Set<Id> existing = new Set<Id>();
    for (PermissionSetGroupComponent comp : [
      SELECT PermissionSetId
      FROM PermissionSetGroupComponent
      WHERE
        PermissionSetGroupId = :groupId
        AND PermissionSetId IN :permissionSetIds
    ]) {
      existing.add(comp.PermissionSetId);
    }

    List<PermissionSetGroupComponent> toInsert = new List<PermissionSetGroupComponent>();
    for (Id psId : permissionSetIds) {
      if (!existing.contains(psId)) {
        toInsert.add(
          new PermissionSetGroupComponent(
            PermissionSetGroupId = groupId,
            PermissionSetId = psId
          )
        );
      }
    }
    if (!toInsert.isEmpty()) {
      insert toInsert;
    }
    return new AdminSecurityDataModel.DmlResult(
      true,
      toInsert.size() +
      ' permission set(s) added to the group. The group is recalculating.'
    );
  }

  /**
   * @description Remove a permission set component from a group.
   */
  public static AdminSecurityDataModel.DmlResult removePermissionSetFromGroup(
    Id groupId,
    Id permissionSetId
  ) {
    verifyAdminAccess();
    if (groupId == null || permissionSetId == null) {
      throw new AuraHandledException(
        'Group ID and permission set are required.'
      );
    }
    List<PermissionSetGroupComponent> comps = [
      SELECT Id
      FROM PermissionSetGroupComponent
      WHERE
        PermissionSetGroupId = :groupId
        AND PermissionSetId = :permissionSetId
    ];
    if (comps.isEmpty()) {
      return new AdminSecurityDataModel.DmlResult(
        true,
        'That permission set is not part of the group.'
      );
    }
    delete comps;
    return new AdminSecurityDataModel.DmlResult(
      true,
      'Permission set removed from the group. The group is recalculating.'
    );
  }

  /**
   * @description Turn free text into a valid developer name: starts with a letter, only
   * letters/digits/underscores, no doubled or trailing underscores, max 40 chars.
   */
  private static String sanitizeDeveloperName(String raw) {
    String name = raw.trim()
      .replaceAll('[^a-zA-Z0-9]+', '_')
      .replaceAll('_+', '_');
    name = name.removeStart('_').removeEnd('_');
    if (String.isBlank(name)) {
      return null;
    }
    if (!Pattern.matches('^[a-zA-Z].*', name)) {
      name = 'X_' + name;
    }
    if (name.length() > 40) {
      name = name.substring(0, 40).removeEnd('_');
    }
    return name;
  }

  /**
   * @description Fetch all profiles with associated user counts
   */
  public static List<AdminSecurityDataModel.ProfileSummary> getProfiles(
    String searchTerm,
    String licenseFilter
  ) {
    verifyAdminAccess();

    String query = 'SELECT Id, Name, UserType, Description, UserLicense.Name, CreatedDate FROM Profile';
    List<String> conditions = new List<String>();

    if (String.isNotBlank(licenseFilter) && licenseFilter != 'All') {
      conditions.add('UserLicense.Name = :licenseFilter');
    }

    if (String.isNotBlank(searchTerm)) {
      String term = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
      conditions.add('(Name LIKE :term OR Description LIKE :term)');
    }

    if (!conditions.isEmpty()) {
      query += ' WHERE ' + String.join(conditions, ' AND ');
    }

    query += ' ORDER BY Name ASC LIMIT 150';

    List<Profile> profList = Database.query(query);
    Set<Id> profIds = new Set<Id>();
    for (Profile p : profList) {
      profIds.add(p.Id);
    }

    // Associated users count
    Map<Id, Integer> userCountMap = new Map<Id, Integer>();
    if (!profIds.isEmpty()) {
      List<AggregateResult> aggResults = [
        SELECT ProfileId, COUNT(Id) cnt
        FROM User
        WHERE ProfileId IN :profIds
        GROUP BY ProfileId
      ];
      for (AggregateResult ar : aggResults) {
        userCountMap.put((Id) ar.get('ProfileId'), (Integer) ar.get('cnt'));
      }
    }

    // Find matching profile-owned PermissionSets
    Map<Id, Id> profToPsMap = new Map<Id, Id>();
    Map<Id, Boolean> profCustomMap = new Map<Id, Boolean>();
    if (!profIds.isEmpty()) {
      List<PermissionSet> permSets = [
        SELECT Id, ProfileId, IsCustom
        FROM PermissionSet
        WHERE IsOwnedByProfile = TRUE AND ProfileId IN :profIds
      ];
      for (PermissionSet ps : permSets) {
        profToPsMap.put(ps.ProfileId, ps.Id);
        profCustomMap.put(ps.ProfileId, ps.IsCustom);
      }
    }

    List<AdminSecurityDataModel.ProfileSummary> results = new List<AdminSecurityDataModel.ProfileSummary>();
    for (Profile p : profList) {
      AdminSecurityDataModel.ProfileSummary dto = new AdminSecurityDataModel.ProfileSummary();
      dto.id = p.Id;
      dto.name = p.Name;
      dto.userType = p.UserType;
      dto.userLicenseName = p.UserLicense != null ? p.UserLicense.Name : 'None';
      dto.description = p.Description;
      dto.userCount = userCountMap.containsKey(p.Id)
        ? userCountMap.get(p.Id)
        : 0;
      dto.permissionSetId = profToPsMap.get(p.Id);
      dto.createdDateFormatted = p.CreatedDate != null
        ? p.CreatedDate.format('yyyy-MM-dd')
        : '-';
      dto.isCustom = profCustomMap.containsKey(p.Id)
        ? profCustomMap.get(p.Id)
        : false;
      results.add(dto);
    }

    results.sort();
    return results;
  }

  /**
   * @description Fetch details of a specific profile: users, object perms, and key system privileges
   */
  public static AdminSecurityDataModel.ProfileDetail getProfileDetail(
    Id profileId
  ) {
    verifyAdminAccess();

    if (profileId == null) {
      throw new AuraHandledException('Profile ID cannot be blank.');
    }

    Profile p = [
      SELECT
        Id,
        Name,
        UserType,
        Description,
        UserLicense.Name,
        CreatedDate,
        PermissionsModifyAllData,
        PermissionsViewAllData,
        PermissionsApiEnabled,
        PermissionsViewSetup,
        PermissionsCustomizeApplication,
        PermissionsAuthorApex,
        PermissionsPasswordNeverExpires
      FROM Profile
      WHERE Id = :profileId
      LIMIT 1
    ];

    AdminSecurityDataModel.ProfileSummary summary = new AdminSecurityDataModel.ProfileSummary();
    summary.id = p.Id;
    summary.name = p.Name;
    summary.userType = p.UserType;
    summary.userLicenseName = p.UserLicense != null
      ? p.UserLicense.Name
      : 'None';
    summary.description = p.Description;
    summary.createdDateFormatted = p.CreatedDate != null
      ? p.CreatedDate.format('yyyy-MM-dd')
      : '-';

    // Associated users
    List<User> userList = [
      SELECT Id, Name, Username, Email, IsActive, UserRole.Name, SmallPhotoUrl
      FROM User
      WHERE ProfileId = :profileId
      ORDER BY Name ASC
      LIMIT 200
    ];

    List<AdminSecurityDataModel.AdminUserInfo> users = new List<AdminSecurityDataModel.AdminUserInfo>();
    for (User u : userList) {
      AdminSecurityDataModel.AdminUserInfo uDto = new AdminSecurityDataModel.AdminUserInfo();
      uDto.userId = u.Id;
      uDto.name = u.Name;
      uDto.username = u.Username;
      uDto.email = u.Email;
      uDto.isActive = u.IsActive;
      uDto.statusBadge = u.IsActive ? 'Active' : 'Inactive';
      uDto.roleName = u.UserRole != null ? u.UserRole.Name : '-';
      users.add(uDto);
    }
    summary.userCount = users.size();

    // Profile-owned PermissionSet Id
    List<PermissionSet> permSets = [
      SELECT Id, IsCustom
      FROM PermissionSet
      WHERE IsOwnedByProfile = TRUE AND ProfileId = :profileId
      LIMIT 1
    ];

    List<AdminSecurityDataModel.ObjectPermItem> objPerms = new List<AdminSecurityDataModel.ObjectPermItem>();
    if (!permSets.isEmpty()) {
      Id permSetId = permSets[0].Id;
      summary.permissionSetId = permSetId;
      summary.isCustom = permSets[0].IsCustom;

      List<ObjectPermissions> opList = [
        SELECT
          Id,
          SobjectType,
          PermissionsRead,
          PermissionsCreate,
          PermissionsEdit,
          PermissionsDelete,
          PermissionsViewAllRecords,
          PermissionsModifyAllRecords
        FROM ObjectPermissions
        WHERE ParentId = :permSetId
        ORDER BY SobjectType ASC
        LIMIT 200
      ];

      Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
      for (ObjectPermissions op : opList) {
        AdminSecurityDataModel.ObjectPermItem item = new AdminSecurityDataModel.ObjectPermItem();
        item.id = op.Id;
        item.parentId = permSetId;
        item.parentName = p.Name;
        item.parentType = 'Profile';
        item.sobjectType = op.SobjectType;
        item.isCustomObject = op.SobjectType.endsWith('__c');
        if (gd.containsKey(op.SobjectType.toLowerCase())) {
          item.sobjectLabel = gd.get(op.SobjectType.toLowerCase())
            .getDescribe()
            .getLabel();
        } else {
          item.sobjectLabel = op.SobjectType;
        }
        item.permissionsRead = op.PermissionsRead;
        item.permissionsCreate = op.PermissionsCreate;
        item.permissionsEdit = op.PermissionsEdit;
        item.permissionsDelete = op.PermissionsDelete;
        item.permissionsViewAllRecords = op.PermissionsViewAllRecords;
        item.permissionsModifyAllRecords = op.PermissionsModifyAllRecords;
        item.isEditable = false; // Profiles are Metadata Managed via Setup
        objPerms.add(item);
      }
    }

    // Key System Permissions
    List<AdminSecurityDataModel.KeySystemPermission> sysPerms = new List<AdminSecurityDataModel.KeySystemPermission>();
    sysPerms.add(
      new AdminSecurityDataModel.KeySystemPermission(
        'Modify All Data',
        'Modify All Data',
        'Grants full administrative access across all records and objects',
        p.PermissionsModifyAllData,
        'Administrative'
      )
    );
    sysPerms.add(
      new AdminSecurityDataModel.KeySystemPermission(
        'View All Data',
        'View All Data',
        'Grants read access to all standard and custom data records',
        p.PermissionsViewAllData,
        'Administrative'
      )
    );
    sysPerms.add(
      new AdminSecurityDataModel.KeySystemPermission(
        'API Enabled',
        'API Enabled',
        'Allows integration and API login via REST, SOAP, and Bulk APIs',
        p.PermissionsApiEnabled,
        'Integration'
      )
    );
    sysPerms.add(
      new AdminSecurityDataModel.KeySystemPermission(
        'View Setup',
        'View Setup and Configuration',
        'Grants access to explore administrative Setup pages and metadata',
        p.PermissionsViewSetup,
        'Administrative'
      )
    );
    sysPerms.add(
      new AdminSecurityDataModel.KeySystemPermission(
        'Customize Application',
        'Customize Application',
        'Allows creating and editing custom objects, fields, and apps',
        p.PermissionsCustomizeApplication,
        'Configuration'
      )
    );
    sysPerms.add(
      new AdminSecurityDataModel.KeySystemPermission(
        'Author Apex',
        'Author Apex',
        'Permits writing, executing, and deploying Apex triggers and classes',
        p.PermissionsAuthorApex,
        'Development'
      )
    );
    sysPerms.add(
      new AdminSecurityDataModel.KeySystemPermission(
        'Password Never Expires',
        'Password Never Expires',
        'Exempts user from standard org password rotation policies',
        p.PermissionsPasswordNeverExpires,
        'Security'
      )
    );

    AdminSecurityDataModel.ProfileDetail detail = new AdminSecurityDataModel.ProfileDetail();
    detail.profile = summary;
    detail.associatedUsers = users;
    detail.objectPermissions = objPerms;
    detail.systemPermissions = sysPerms;

    return detail;
  }

  /**
   * @description Fetch object-level permissions for a selected Permission Set or Profile
   */
  public static AdminSecurityDataModel.ObjectPermPage getObjectPermissionsForTarget(
    Id parentId,
    String targetType,
    String searchTerm,
    Integer pageNumber,
    Integer pageSize
  ) {
    verifyAdminAccess();

    if (parentId == null) {
      throw new AuraHandledException('Target ID cannot be blank.');
    }

    String parentName = '';
    Boolean isEditable = false;
    Set<Id> permSetIds = new Set<Id>();

    if (targetType == 'Profile') {
      List<PermissionSet> pList = [
        SELECT Id, Profile.Name
        FROM PermissionSet
        WHERE ProfileId = :parentId
        LIMIT 1
      ];
      if (pList.isEmpty()) {
        throw new AuraHandledException(
          'No underlying Permission Set found for profile.'
        );
      }
      permSetIds.add(pList[0].Id);
      parentName = pList[0].Profile.Name;
      isEditable = false;
    } else if (targetType == 'User') {
      List<User> uList = [
        SELECT Id, Name, ProfileId, Profile.Name, Profile.UserLicense.Name
        FROM User
        WHERE Id = :parentId
        LIMIT 1
      ];
      if (uList.isEmpty()) {
        throw new AuraHandledException('User not found.');
      }
      User u = uList[0];
      String licName = u.Profile != null && u.Profile.UserLicense != null
        ? u.Profile.UserLicense.Name
        : (u.Profile != null ? u.Profile.Name : 'Standard');
      parentName = u.Name + ' (' + licName + ')';
      isEditable = false;

      if (u.ProfileId != null) {
        for (PermissionSet pps : [
          SELECT Id FROM PermissionSet WHERE ProfileId = :u.ProfileId LIMIT 1
        ]) {
          permSetIds.add(pps.Id);
        }
      }
      for (PermissionSetAssignment psa : [
        SELECT PermissionSetId
        FROM PermissionSetAssignment
        WHERE AssigneeId = :u.Id
      ]) {
        if (psa.PermissionSetId != null) {
          permSetIds.add(psa.PermissionSetId);
        }
      }
    } else {
      PermissionSet ps = [
        SELECT Id, Label, IsCustom, IsOwnedByProfile
        FROM PermissionSet
        WHERE Id = :parentId
        LIMIT 1
      ];
      permSetIds.add(ps.Id);
      parentName = ps.Label;
      isEditable = (ps.IsCustom && !ps.IsOwnedByProfile);
    }

    String filters = ' WHERE ParentId IN :permSetIds';
    String term = '';
    if (String.isNotBlank(searchTerm)) {
      term = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
      filters += ' AND SobjectType LIKE :term';
    }

    String query =
      'SELECT Id, ParentId, SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete, PermissionsViewAllRecords, PermissionsModifyAllRecords FROM ObjectPermissions' +
      filters +
      ' ORDER BY SobjectType ASC LIMIT 1000';

    List<ObjectPermissions> opList = Database.query(query);
    Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();

    Map<String, AdminSecurityDataModel.ObjectPermItem> mergedMap = new Map<String, AdminSecurityDataModel.ObjectPermItem>();
    for (ObjectPermissions op : opList) {
      if (!mergedMap.containsKey(op.SobjectType)) {
        AdminSecurityDataModel.ObjectPermItem item = new AdminSecurityDataModel.ObjectPermItem();
        item.id = op.Id;
        item.parentId = parentId;
        item.parentName = parentName;
        item.parentType = targetType;
        item.sobjectType = op.SobjectType;
        item.isCustomObject = op.SobjectType.endsWith('__c');
        if (gd.containsKey(op.SobjectType.toLowerCase())) {
          item.sobjectLabel = gd.get(op.SobjectType.toLowerCase())
            .getDescribe()
            .getLabel();
        } else {
          item.sobjectLabel = op.SobjectType;
        }
        item.permissionsRead = op.PermissionsRead;
        item.permissionsCreate = op.PermissionsCreate;
        item.permissionsEdit = op.PermissionsEdit;
        item.permissionsDelete = op.PermissionsDelete;
        item.permissionsViewAllRecords = op.PermissionsViewAllRecords;
        item.permissionsModifyAllRecords = op.PermissionsModifyAllRecords;
        item.isEditable = isEditable;
        mergedMap.put(op.SobjectType, item);
      } else {
        AdminSecurityDataModel.ObjectPermItem item = mergedMap.get(op.SobjectType);
        item.permissionsRead = item.permissionsRead || op.PermissionsRead;
        item.permissionsCreate = item.permissionsCreate || op.PermissionsCreate;
        item.permissionsEdit = item.permissionsEdit || op.PermissionsEdit;
        item.permissionsDelete = item.permissionsDelete || op.PermissionsDelete;
        item.permissionsViewAllRecords = item.permissionsViewAllRecords || op.PermissionsViewAllRecords;
        item.permissionsModifyAllRecords = item.permissionsModifyAllRecords || op.PermissionsModifyAllRecords;
      }
    }

    List<AdminSecurityDataModel.ObjectPermItem> allSorted = mergedMap.values();
    allSorted.sort();

    Integer safeSize = (pageSize == null || pageSize <= 0) ? 15 : pageSize;
    Integer safePage = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
    Integer offset = (safePage - 1) * safeSize;
    Integer totalCount = allSorted.size();

    List<AdminSecurityDataModel.ObjectPermItem> results = new List<AdminSecurityDataModel.ObjectPermItem>();
    Integer startIdx = offset;
    Integer endIdx = Math.min(startIdx + safeSize, totalCount);
    for (Integer i = startIdx; i < endIdx; i++) {
      results.add(allSorted[i]);
    }

    AdminSecurityDataModel.ObjectPermPage page = new AdminSecurityDataModel.ObjectPermPage();
    page.records = results;
    page.totalCount = totalCount;
    return page;
  }

  /**
   * @description Fetch field-level security for a specific object in a Profile or Permission Set
   */
  public static AdminSecurityDataModel.FieldPermPage getFieldPermissionsForTarget(
    Id parentId,
    String targetType,
    String sobjectType,
    String searchTerm,
    Integer pageNumber,
    Integer pageSize
  ) {
    verifyAdminAccess();

    if (parentId == null || String.isBlank(sobjectType)) {
      throw new AuraHandledException(
        'Target ID and Object Name cannot be blank.'
      );
    }

    String parentName = '';
    Boolean isEditable = false;
    Set<Id> permSetIds = new Set<Id>();

    if (targetType == 'Profile') {
      List<PermissionSet> pList = [
        SELECT Id, Profile.Name
        FROM PermissionSet
        WHERE ProfileId = :parentId
        LIMIT 1
      ];
      if (pList.isEmpty()) {
        throw new AuraHandledException(
          'No underlying Permission Set found for profile.'
        );
      }
      permSetIds.add(pList[0].Id);
      parentName = pList[0].Profile.Name;
      isEditable = false;
    } else if (targetType == 'User') {
      List<User> uList = [
        SELECT Id, Name, ProfileId, Profile.Name, Profile.UserLicense.Name
        FROM User
        WHERE Id = :parentId
        LIMIT 1
      ];
      if (uList.isEmpty()) {
        throw new AuraHandledException('User not found.');
      }
      User u = uList[0];
      String licName = u.Profile != null && u.Profile.UserLicense != null
        ? u.Profile.UserLicense.Name
        : (u.Profile != null ? u.Profile.Name : 'Standard');
      parentName = u.Name + ' (' + licName + ')';
      isEditable = false;

      if (u.ProfileId != null) {
        for (PermissionSet pps : [
          SELECT Id FROM PermissionSet WHERE ProfileId = :u.ProfileId LIMIT 1
        ]) {
          permSetIds.add(pps.Id);
        }
      }
      for (PermissionSetAssignment psa : [
        SELECT PermissionSetId
        FROM PermissionSetAssignment
        WHERE AssigneeId = :u.Id
      ]) {
        if (psa.PermissionSetId != null) {
          permSetIds.add(psa.PermissionSetId);
        }
      }
    } else {
      PermissionSet ps = [
        SELECT Id, Label, IsCustom, IsOwnedByProfile
        FROM PermissionSet
        WHERE Id = :parentId
        LIMIT 1
      ];
      permSetIds.add(ps.Id);
      parentName = ps.Label;
      isEditable = (ps.IsCustom && !ps.IsOwnedByProfile);
    }

    // Schema describe for fields
    Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
    if (!gd.containsKey(sobjectType.toLowerCase())) {
      throw new AuraHandledException('Object not found: ' + sobjectType);
    }

    Map<String, Schema.SObjectField> fieldMap = gd.get(
        sobjectType.toLowerCase()
      )
      .getDescribe()
      .fields.getMap();

    // Existing FieldPermissions
    List<FieldPermissions> existingFpList = [
      SELECT Id, ParentId, SobjectType, Field, PermissionsRead, PermissionsEdit
      FROM FieldPermissions
      WHERE ParentId IN :permSetIds AND SobjectType = :sobjectType
      LIMIT 1000
    ];

    Map<String, Boolean> fpReadMap = new Map<String, Boolean>();
    Map<String, Boolean> fpEditMap = new Map<String, Boolean>();
    for (FieldPermissions fp : existingFpList) {
      String fKey = fp.Field.toLowerCase();
      Boolean curR = fpReadMap.containsKey(fKey) ? fpReadMap.get(fKey) : false;
      Boolean curE = fpEditMap.containsKey(fKey) ? fpEditMap.get(fKey) : false;
      fpReadMap.put(fKey, curR || fp.PermissionsRead);
      fpEditMap.put(fKey, curE || fp.PermissionsEdit);
    }

    List<AdminSecurityDataModel.FieldPermItem> results = new List<AdminSecurityDataModel.FieldPermItem>();
    for (String fName : fieldMap.keySet()) {
      Schema.DescribeFieldResult fd = fieldMap.get(fName).getDescribe();

      // Only permissionable fields or standard fields that support FLS
      if (fd.isPermissionable() || fd.isCustom()) {
        String fullFieldName = sobjectType + '.' + fd.getName();

        if (String.isNotBlank(searchTerm)) {
          String lowerTerm = searchTerm.toLowerCase();
          if (
            !fd.getLabel().toLowerCase().contains(lowerTerm) &&
            !fd.getName().toLowerCase().contains(lowerTerm)
          ) {
            continue;
          }
        }

        AdminSecurityDataModel.FieldPermItem item = new AdminSecurityDataModel.FieldPermItem();
        item.parentId = parentId;
        item.parentName = parentName;
        item.sobjectType = sobjectType;
        item.field = fullFieldName;
        item.fieldLabel = fd.getLabel();
        item.dataType = String.valueOf(fd.getType());
        item.isCustom = fd.isCustom();
        item.isEditable = isEditable;

        String fKey = fullFieldName.toLowerCase();
        item.permissionsRead = fpReadMap.containsKey(fKey) ? fpReadMap.get(fKey) : false;
        item.permissionsEdit = fpEditMap.containsKey(fKey) ? fpEditMap.get(fKey) : false;
        item.id = null;
        results.add(item);
      }
    }

    results.sort();

    // In-memory pagination (field lists come from describe, not SOQL).
    Integer safeSize = (pageSize == null || pageSize <= 0) ? 15 : pageSize;
    Integer safePage = (pageNumber == null || pageNumber < 1) ? 1 : pageNumber;
    Integer total = results.size();
    Integer startIdx = (safePage - 1) * safeSize;
    List<AdminSecurityDataModel.FieldPermItem> pageRows = new List<AdminSecurityDataModel.FieldPermItem>();
    if (startIdx < total) {
      Integer endIdx = Math.min(startIdx + safeSize, total);
      for (Integer i = startIdx; i < endIdx; i++) {
        pageRows.add(results[i]);
      }
    }

    AdminSecurityDataModel.FieldPermPage page = new AdminSecurityDataModel.FieldPermPage();
    page.records = pageRows;
    page.totalCount = total;
    return page;
  }

  /**
   * @description Fetch applications and their accessibility across profiles and permission sets
   */
  public static List<AdminSecurityDataModel.AppAccessSummary> getAppAccessList(
    String searchTerm
  ) {
    return getAppAccessList(searchTerm, 'All');
  }

  public static List<AdminSecurityDataModel.AppAccessSummary> getAppAccessList(
    String searchTerm,
    String typeFilter
  ) {
    verifyAdminAccess();

    String query = 'SELECT Id, Name, Label, Description, Type, IsVisible, IsAccessible, ApplicationId, NamespacePrefix FROM AppMenuItem WHERE Type = \'TabSet\'';
    if (String.isNotBlank(searchTerm)) {
      String term = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
      query += ' AND (Name LIKE :term OR Label LIKE :term OR Description LIKE :term)';
    }
    query += ' ORDER BY Label ASC LIMIT 200';

    List<AppMenuItem> menuItems = Database.query(query);

    // Map AppDefinition by 15-char suffix and DeveloperName
    Map<String, AppDefinition> appDefBySuffix = new Map<String, AppDefinition>();
    Map<String, AppDefinition> appDefByName = new Map<String, AppDefinition>();
    for (AppDefinition ad : [
      SELECT DurableId, Label, DeveloperName, Description, NavType, HeaderColor
      FROM AppDefinition
    ]) {
      if (ad.DurableId != null && ad.DurableId.length() >= 15) {
        appDefBySuffix.put(ad.DurableId.substring(3), ad);
      }
      if (String.isNotBlank(ad.DeveloperName)) {
        appDefByName.put(ad.DeveloperName.toLowerCase(), ad);
      }
    }

    // Fetch SetupEntityAccess for apps
    List<SetupEntityAccess> seaList = [
      SELECT
        SetupEntityId,
        ParentId,
        Parent.Name,
        Parent.Label,
        Parent.IsOwnedByProfile,
        Parent.Profile.Name
      FROM SetupEntityAccess
      WHERE SetupEntityType = 'TabSet'
      LIMIT 1000
    ];

    Map<Id, List<String>> appProfilesMap = new Map<Id, List<String>>();
    Map<Id, List<String>> appPermSetsMap = new Map<Id, List<String>>();

    for (SetupEntityAccess sea : seaList) {
      if (sea.Parent.IsOwnedByProfile && sea.Parent.Profile != null) {
        if (!appProfilesMap.containsKey(sea.SetupEntityId)) {
          appProfilesMap.put(sea.SetupEntityId, new List<String>());
        }
        appProfilesMap.get(sea.SetupEntityId).add(sea.Parent.Profile.Name);
      } else if (sea.Parent != null) {
        if (!appPermSetsMap.containsKey(sea.SetupEntityId)) {
          appPermSetsMap.put(sea.SetupEntityId, new List<String>());
        }
        appPermSetsMap.get(sea.SetupEntityId).add(sea.Parent.Label);
      }
    }

    List<AdminSecurityDataModel.AppAccessSummary> results = new List<AdminSecurityDataModel.AppAccessSummary>();
    for (AppMenuItem item : menuItems) {
      Boolean isCustom = (item.NamespacePrefix != 'standard');
      if ('Custom'.equalsIgnoreCase(typeFilter) && !isCustom) {
        continue;
      }
      if ('Standard'.equalsIgnoreCase(typeFilter) && isCustom) {
        continue;
      }

      AdminSecurityDataModel.AppAccessSummary dto = new AdminSecurityDataModel.AppAccessSummary();
      dto.id = item.Id;
      dto.label = item.Label;
      dto.developerName = item.Name;
      dto.description = item.Description != null
        ? item.Description
        : 'Standard Salesforce Application';
      dto.type = item.Type;
      dto.isVisible = item.IsVisible;
      dto.isAccessible = item.IsAccessible;
      dto.isCustom = isCustom;

      Id appId = item.ApplicationId != null ? item.ApplicationId : item.Id;
      dto.applicationId = String.valueOf(appId);

      // Match AppDefinition
      AppDefinition matchedDef = null;
      if (item.ApplicationId != null) {
        String appIdStr = String.valueOf(item.ApplicationId);
        if (appIdStr.length() >= 15) {
          matchedDef = appDefBySuffix.get(appIdStr.substring(3));
        }
      }
      if (matchedDef == null && String.isNotBlank(item.Name)) {
        matchedDef = appDefByName.get(item.Name.toLowerCase());
      }

      if (matchedDef != null) {
        dto.appDefinitionId = matchedDef.DurableId;
        dto.navType = matchedDef.NavType;
        dto.headerColor = matchedDef.HeaderColor;
      } else if (item.ApplicationId != null) {
        String appIdStr = String.valueOf(item.ApplicationId);
        if (appIdStr.startsWith('02u') && appIdStr.length() >= 15) {
          dto.appDefinitionId = '06m' + appIdStr.substring(3);
        }
        dto.navType = 'Standard';
        dto.headerColor = '#0176D3';
      }

      List<String> profList = appProfilesMap.containsKey(appId)
        ? appProfilesMap.get(appId)
        : new List<String>();
      List<String> psList = appPermSetsMap.containsKey(appId)
        ? appPermSetsMap.get(appId)
        : new List<String>();

      dto.profilesWithAccess = profList;
      dto.profilesCount = profList.size();
      dto.permSetsWithAccess = psList;
      dto.permSetsCount = psList.size();
      dto.setupUrl = '/lightning/setup/AppManager/home';
      results.add(dto);
    }

    results.sort();
    return results;
  }

  /**
   * @description Get comprehensive detail view for an App including tabs, objects used, and profile access
   */
  public static AdminSecurityDataModel.AppDetailView getAppDetail(
    String applicationId,
    String appDefinitionId
  ) {
    verifyAdminAccess();

    if (String.isBlank(applicationId) && String.isBlank(appDefinitionId)) {
      throw new AuraHandledException('App ID or Definition ID is required.');
    }

    if (String.isBlank(applicationId) && String.isNotBlank(appDefinitionId)) {
      if (appDefinitionId.startsWith('06m') && appDefinitionId.length() >= 15) {
        applicationId = '02u' + appDefinitionId.substring(3);
      }
    }
    if (String.isBlank(appDefinitionId) && String.isNotBlank(applicationId)) {
      if (applicationId.startsWith('02u') && applicationId.length() >= 15) {
        appDefinitionId = '06m' + applicationId.substring(3);
      }
    }

    List<AppMenuItem> menuItems = [
      SELECT Id, Name, Label, Description, Type, IsVisible, IsAccessible, ApplicationId, NamespacePrefix
      FROM AppMenuItem
      WHERE ApplicationId = :applicationId OR Id = :applicationId
      LIMIT 1
    ];
    AppMenuItem menuItem = menuItems.isEmpty() ? null : menuItems[0];

    List<AppDefinition> appDefs = [
      SELECT DurableId, Label, DeveloperName, Description, NavType, HeaderColor
      FROM AppDefinition
      WHERE DurableId = :appDefinitionId
      LIMIT 1
    ];
    AppDefinition appDef = appDefs.isEmpty() ? null : appDefs[0];

    AdminSecurityDataModel.AppAccessSummary appDto = new AdminSecurityDataModel.AppAccessSummary();
    if (menuItem != null) {
      appDto.id = menuItem.Id;
      appDto.applicationId = String.valueOf(menuItem.ApplicationId);
      appDto.label = appDef != null ? appDef.Label : menuItem.Label;
      appDto.developerName = appDef != null ? appDef.DeveloperName : menuItem.Name;
      appDto.description = appDef != null && String.isNotBlank(appDef.Description)
        ? appDef.Description
        : (menuItem.Description != null ? menuItem.Description : 'Salesforce Application');
      appDto.isCustom = (menuItem.NamespacePrefix != 'standard');
      appDto.type = menuItem.Type;
      appDto.isVisible = menuItem.IsVisible;
      appDto.isAccessible = menuItem.IsAccessible;
    } else if (appDef != null) {
      appDto.id = appDef.DurableId;
      appDto.applicationId = applicationId;
      appDto.label = appDef.Label;
      appDto.developerName = appDef.DeveloperName;
      appDto.description = appDef.Description;
      appDto.isCustom = (appDef.DeveloperName != null && (appDef.DeveloperName.contains('__') || !appDef.DeveloperName.startsWith('standard')));
      appDto.type = 'TabSet';
      appDto.isVisible = true;
      appDto.isAccessible = true;
    }
    appDto.appDefinitionId = appDefinitionId;
    appDto.navType = appDef != null && String.isNotBlank(appDef.NavType) ? appDef.NavType : 'Standard';
    appDto.headerColor = appDef != null && String.isNotBlank(appDef.HeaderColor) ? appDef.HeaderColor : '#0176D3';
    appDto.setupUrl = '/lightning/setup/AppManager/home';

    // Tabs & Objects
    List<AdminSecurityDataModel.AppTabItem> tabItems = new List<AdminSecurityDataModel.AppTabItem>();
    Map<String, AdminSecurityDataModel.AppObjectItem> objectMap = new Map<String, AdminSecurityDataModel.AppObjectItem>();

    if (String.isNotBlank(appDefinitionId)) {
      List<AppTabMember> tabMembers = [
        SELECT DurableId, TabDefinitionId, SortOrder
        FROM AppTabMember
        WHERE AppDefinitionId = :appDefinitionId
        ORDER BY SortOrder ASC
      ];

      Set<String> tabDefIds = new Set<String>();
      for (AppTabMember m : tabMembers) {
        if (String.isNotBlank(m.TabDefinitionId)) {
          tabDefIds.add(m.TabDefinitionId);
        }
      }

      Map<String, TabDefinition> tabDefMap = new Map<String, TabDefinition>();
      if (!tabDefIds.isEmpty()) {
        for (TabDefinition td : [
          SELECT DurableId, Label, Name, SobjectName, IsCustom
          FROM TabDefinition
          WHERE DurableId IN :tabDefIds
        ]) {
          tabDefMap.put(td.DurableId, td);
        }
      }

      Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

      for (AppTabMember m : tabMembers) {
        TabDefinition td = tabDefMap.get(m.TabDefinitionId);
        if (td == null) {
          continue;
        }

        AdminSecurityDataModel.AppTabItem tabItem = new AdminSecurityDataModel.AppTabItem();
        tabItem.id = td.DurableId;
        tabItem.sortOrder = m.SortOrder;
        tabItem.tabLabel = td.Label;
        tabItem.tabName = td.Name;
        tabItem.sobjectName = td.SobjectName;
        tabItem.isCustom = td.IsCustom;

        Boolean isObject = (String.isNotBlank(td.SobjectName) && !td.SobjectName.startsWith('0R'));
        tabItem.isObjectTab = isObject;

        if (isObject) {
          Schema.SObjectType sObjType = globalDescribe.get(td.SobjectName.toLowerCase());
          if (sObjType != null) {
            Schema.DescribeSObjectResult describe = sObjType.getDescribe();
            tabItem.sobjectLabel = describe.getLabel();
            tabItem.fieldCount = describe.fields.getMap().size();

            String objKey = td.SobjectName.toLowerCase();
            if (!objectMap.containsKey(objKey)) {
              AdminSecurityDataModel.AppObjectItem objItem = new AdminSecurityDataModel.AppObjectItem();
              objItem.apiName = describe.getName();
              objItem.label = describe.getLabel();
              objItem.isCustom = describe.isCustom();
              objItem.fieldCount = describe.fields.getMap().size();
              objItem.usedInTabs = new List<String>{ td.Label };
              objectMap.put(objKey, objItem);
            } else {
              AdminSecurityDataModel.AppObjectItem existingObj = objectMap.get(objKey);
              if (!existingObj.usedInTabs.contains(td.Label)) {
                existingObj.usedInTabs.add(td.Label);
              }
            }
          } else {
            tabItem.sobjectLabel = td.SobjectName;
            tabItem.fieldCount = 0;
          }
        } else {
          tabItem.sobjectLabel = 'Web / Lightning Component';
          tabItem.fieldCount = 0;
        }

        tabItems.add(tabItem);
      }
    }

    tabItems.sort();
    List<AdminSecurityDataModel.AppObjectItem> objectsList = objectMap.values();
    objectsList.sort();

    // Profile Access
    List<PermissionSet> profilePermSets = [
      SELECT Id, ProfileId, Profile.Name, Profile.UserLicense.Name
      FROM PermissionSet
      WHERE IsOwnedByProfile = true AND ProfileId != null
      ORDER BY Profile.Name ASC
    ];

    Id targetAppId = (menuItem != null && menuItem.ApplicationId != null) ? menuItem.ApplicationId : (Id)applicationId;
    List<SetupEntityAccess> seaList = [
      SELECT Id, ParentId, Parent.ProfileId
      FROM SetupEntityAccess
      WHERE SetupEntityType = 'TabSet' AND SetupEntityId = :targetAppId
    ];

    Set<Id> profilesWithAccess = new Set<Id>();
    for (SetupEntityAccess sea : seaList) {
      if (sea.Parent != null && sea.Parent.ProfileId != null) {
        profilesWithAccess.add(sea.Parent.ProfileId);
      }
    }

    Boolean isStandardApp = (appDto.isCustom == false);
    List<AdminSecurityDataModel.AppProfileAccessItem> profileAccessList = new List<AdminSecurityDataModel.AppProfileAccessItem>();
    for (PermissionSet ps : profilePermSets) {
      AdminSecurityDataModel.AppProfileAccessItem pItem = new AdminSecurityDataModel.AppProfileAccessItem();
      pItem.profileId = ps.ProfileId;
      pItem.profileName = ps.Profile.Name;
      pItem.userLicenseName = ps.Profile.UserLicense != null ? ps.Profile.UserLicense.Name : 'Standard';
      pItem.permissionSetId = ps.Id;
      pItem.hasAccess = profilesWithAccess.contains(ps.ProfileId);

      String licenseLower = pItem.userLicenseName.toLowerCase();
      if (!pItem.hasAccess && isStandardApp && (licenseLower.contains('guest') || licenseLower.contains('chatter free') || licenseLower.contains('minimum access'))) {
        pItem.isRestricted = true;
        pItem.restrictionReason = pItem.userLicenseName + ' profiles cannot access standard Salesforce applications (platform limit: 0).';
      } else {
        pItem.isRestricted = false;
        pItem.restrictionReason = null;
      }

      profileAccessList.add(pItem);
    }
    profileAccessList.sort();

    appDto.tabCount = tabItems.size();
    appDto.objectCount = objectsList.size();
    appDto.profilesCount = profilesWithAccess.size();

    AdminSecurityDataModel.AppDetailView detailView = new AdminSecurityDataModel.AppDetailView();
    detailView.app = appDto;
    detailView.tabs = tabItems;
    detailView.objects = objectsList;
    detailView.profiles = profileAccessList;
    detailView.totalTabs = tabItems.size();
    detailView.totalObjects = objectsList.size();
    detailView.totalProfilesWithAccess = profilesWithAccess.size();

    return detailView;
  }

  /**
   * @description Get field list for an object used by an app
   */
  public static List<AdminSecurityDataModel.AppObjectField> getAppObjectFields(String sobjectType) {
    verifyAdminAccess();
    if (String.isBlank(sobjectType)) {
      return new List<AdminSecurityDataModel.AppObjectField>();
    }

    Schema.SObjectType objType = Schema.getGlobalDescribe().get(sobjectType.toLowerCase());
    if (objType == null) {
      return new List<AdminSecurityDataModel.AppObjectField>();
    }

    Schema.DescribeSObjectResult describe = objType.getDescribe();
    List<AdminSecurityDataModel.AppObjectField> fields = new List<AdminSecurityDataModel.AppObjectField>();

    for (Schema.SObjectField f : describe.fields.getMap().values()) {
      Schema.DescribeFieldResult fd = f.getDescribe();
      AdminSecurityDataModel.AppObjectField item = new AdminSecurityDataModel.AppObjectField();
      item.apiName = fd.getName();
      item.label = fd.getLabel();
      item.dataType = String.valueOf(fd.getType());
      item.isCustom = fd.isCustom();
      item.isRequired = !fd.isNillable() && !fd.isDefaultedOnCreate();
      fields.add(item);
    }

    fields.sort();
    return fields;
  }

  /**
   * @description Cleans raw Salesforce DML and database exception messages into clear, friendly text
   */
  public static String cleanExceptionMessage(Exception ex, String profileName, String licenseName) {
    if (ex == null) {
      return 'An unexpected error occurred.';
    }
    String msg = ex.getMessage();
    if (String.isBlank(msg)) {
      return 'An unexpected error occurred.';
    }

    if (msg.contains('TABSET_LIMIT_EXCEEDED')) {
      String lic = String.isNotBlank(licenseName) ? licenseName : 'this license';
      String prof = String.isNotBlank(profileName) ? 'Profile "' + profileName + '"' : 'This profile';
      return prof + ' cannot be assigned to this application because Salesforce does not permit "' + lic + '" profiles to access standard applications (license limit: 0 standard apps).';
    }
    if (msg.contains('DUPLICATE_VALUE')) {
      return (String.isNotBlank(profileName) ? 'Profile "' + profileName + '"' : 'This profile') + ' already has access to this application.';
    }
    if (msg.contains('INSUFFICIENT_ACCESS')) {
      return 'You do not have sufficient administrative permissions to update application access for Profile "' + (String.isNotBlank(profileName) ? profileName : '') + '".';
    }

    // Clean up generic "Insert failed. First exception on row 0; first error: ERROR_CODE, Message : []"
    if (msg.contains('first error:')) {
      Integer startIdx = msg.indexOf('first error:');
      String sub = msg.substring(startIdx + 12).trim();
      Integer commaIdx = sub.indexOf(',');
      if (commaIdx != -1 && commaIdx < 40) {
        sub = sub.substring(commaIdx + 1).trim();
      }
      if (sub.endsWith(': []')) {
        sub = sub.substring(0, sub.length() - 4).trim();
      } else if (sub.endsWith('[]')) {
        sub = sub.substring(0, sub.length() - 2).trim();
      }
      if (String.isNotBlank(sub)) {
        return sub;
      }
    }

    return msg;
  }

  /**
   * @description Assign profile access to an application
   */
  public static AdminSecurityDataModel.DmlResult assignProfileToApp(
    String applicationId,
    String profileId
  ) {
    verifyAdminAccess();

    if (String.isBlank(applicationId) || String.isBlank(profileId)) {
      return new AdminSecurityDataModel.DmlResult(false, 'Application ID and Profile ID are required.');
    }

    if (applicationId.startsWith('06m') && applicationId.length() >= 15) {
      applicationId = '02u' + applicationId.substring(3);
    }

    List<PermissionSet> permSets = [
      SELECT Id, Profile.Name, Profile.UserLicense.Name
      FROM PermissionSet
      WHERE ProfileId = :profileId AND IsOwnedByProfile = true
      LIMIT 1
    ];
    if (permSets.isEmpty()) {
      return new AdminSecurityDataModel.DmlResult(false, 'Companion Permission Set not found for profile: ' + profileId);
    }
    PermissionSet ps = permSets[0];
    String licenseName = (ps.Profile != null && ps.Profile.UserLicense != null) ? ps.Profile.UserLicense.Name : '';

    List<SetupEntityAccess> existing = [
      SELECT Id
      FROM SetupEntityAccess
      WHERE SetupEntityType = 'TabSet'
        AND SetupEntityId = :applicationId
        AND ParentId = :ps.Id
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return new AdminSecurityDataModel.DmlResult(true, 'Profile ' + ps.Profile.Name + ' already has access to this app.', existing[0].Id);
    }

    // Pre-validate Guest User License restrictions on Standard Apps
    if (licenseName.toLowerCase().contains('guest')) {
      Boolean isStandard = false;
      List<AppMenuItem> apps = [
        SELECT Id, NamespacePrefix 
        FROM AppMenuItem 
        WHERE ApplicationId = :applicationId OR Id = :applicationId 
        LIMIT 1
      ];
      if (!apps.isEmpty() && apps[0].NamespacePrefix == 'standard') {
        isStandard = true;
      } else {
        List<AppDefinition> defs = [
          SELECT DurableId, DeveloperName 
          FROM AppDefinition 
          WHERE DurableId = :applicationId OR DeveloperName = :applicationId 
          LIMIT 1
        ];
        if (!defs.isEmpty() && defs[0].DeveloperName != null && defs[0].DeveloperName.startsWith('standard__')) {
          isStandard = true;
        }
      }
      if (isStandard) {
        return new AdminSecurityDataModel.DmlResult(
          false,
          'Profile "' + ps.Profile.Name + '" cannot be assigned because Salesforce does not permit profiles with the ' + licenseName + ' to access standard applications (license limit: 0 standard apps).'
        );
      }
    }

    try {
      SetupEntityAccess sea = new SetupEntityAccess(
        ParentId = ps.Id,
        SetupEntityId = (Id)applicationId
      );
      insert sea;
      return new AdminSecurityDataModel.DmlResult(true, 'Profile ' + ps.Profile.Name + ' assigned to App successfully.', sea.Id);
    } catch (Exception ex) {
      String friendlyMsg = cleanExceptionMessage(ex, ps.Profile.Name, licenseName);
      return new AdminSecurityDataModel.DmlResult(false, friendlyMsg);
    }
  }

  /**
   * @description Remove profile access from an application
   */
  public static AdminSecurityDataModel.DmlResult removeProfileFromApp(
    String applicationId,
    String profileId
  ) {
    verifyAdminAccess();

    if (String.isBlank(applicationId) || String.isBlank(profileId)) {
      return new AdminSecurityDataModel.DmlResult(false, 'Application ID and Profile ID are required.');
    }

    if (applicationId.startsWith('06m') && applicationId.length() >= 15) {
      applicationId = '02u' + applicationId.substring(3);
    }

    List<PermissionSet> permSets = [
      SELECT Id, Profile.Name, Profile.UserLicense.Name
      FROM PermissionSet
      WHERE ProfileId = :profileId AND IsOwnedByProfile = true
      LIMIT 1
    ];
    if (permSets.isEmpty()) {
      return new AdminSecurityDataModel.DmlResult(false, 'Profile permission set not found.');
    }
    PermissionSet ps = permSets[0];
    String licenseName = (ps.Profile != null && ps.Profile.UserLicense != null) ? ps.Profile.UserLicense.Name : '';

    List<SetupEntityAccess> existing = [
      SELECT Id
      FROM SetupEntityAccess
      WHERE SetupEntityType = 'TabSet'
        AND SetupEntityId = :applicationId
        AND ParentId = :ps.Id
      LIMIT 1
    ];
    if (existing.isEmpty()) {
      return new AdminSecurityDataModel.DmlResult(true, 'Profile ' + ps.Profile.Name + ' does not have access.');
    }

    try {
      delete existing[0];
      return new AdminSecurityDataModel.DmlResult(true, 'Access for ' + ps.Profile.Name + ' removed successfully.');
    } catch (Exception ex) {
      String friendlyMsg = cleanExceptionMessage(ex, ps.Profile.Name, licenseName);
      return new AdminSecurityDataModel.DmlResult(false, friendlyMsg);
    }
  }

  // =========================================================================
  // DML / MUTATION OPERATIONS (SECURITY PROTECTED)
  // =========================================================================

  /**
   * @description Assign a standalone permission set to a user
   */
  public static AdminSecurityDataModel.DmlResult assignPermissionSetToUser(
    Id userId,
    Id permissionSetId
  ) {
    verifyAdminAccess();

    if (userId == null || permissionSetId == null) {
      throw new AuraHandledException(
        'User ID and Permission Set ID are required.'
      );
    }

    PermissionSet ps = [
      SELECT Id, Label, IsOwnedByProfile
      FROM PermissionSet
      WHERE Id = :permissionSetId
      LIMIT 1
    ];
    if (ps.IsOwnedByProfile) {
      throw new AuraHandledException(
        'Profile-owned permission sets cannot be assigned directly. Change the user\'s profile instead.'
      );
    }

    List<PermissionSetAssignment> existing = [
      SELECT Id
      FROM PermissionSetAssignment
      WHERE
        AssigneeId = :userId
        AND PermissionSetId = :permissionSetId
        AND PermissionSetGroupId = NULL
      LIMIT 1
    ];

    if (!existing.isEmpty()) {
      return new AdminSecurityDataModel.DmlResult(
        true,
        'Permission Set is already assigned to this user.',
        existing[0].Id
      );
    }

    PermissionSetAssignment psa = new PermissionSetAssignment(
      AssigneeId = userId,
      PermissionSetId = permissionSetId
    );

    insert psa;
    return new AdminSecurityDataModel.DmlResult(
      true,
      'Permission Set "' + ps.Label + '" successfully assigned.',
      psa.Id
    );
  }

  /**
   * @description Remove a standalone permission set from a user
   */
  public static AdminSecurityDataModel.DmlResult removePermissionSetFromUser(
    Id userId,
    Id permissionSetId
  ) {
    verifyAdminAccess();

    if (userId == null || permissionSetId == null) {
      throw new AuraHandledException(
        'User ID and Permission Set ID are required.'
      );
    }

    List<PermissionSetAssignment> psaList = [
      SELECT Id, PermissionSet.Label
      FROM PermissionSetAssignment
      WHERE
        AssigneeId = :userId
        AND PermissionSetId = :permissionSetId
        AND PermissionSetGroupId = NULL
      LIMIT 1
    ];

    if (psaList.isEmpty()) {
      return new AdminSecurityDataModel.DmlResult(
        true,
        'Assignment record not found or already removed.'
      );
    }

    String label = psaList[0].PermissionSet != null
      ? psaList[0].PermissionSet.Label
      : 'Permission Set';
    delete psaList;
    return new AdminSecurityDataModel.DmlResult(
      true,
      'Permission Set "' + label + '" assignment successfully removed.'
    );
  }

  /**
   * @description Assign a Permission Set Group to a user
   */
  public static AdminSecurityDataModel.DmlResult assignPermissionSetGroupToUser(
    Id userId,
    Id permissionSetGroupId
  ) {
    verifyAdminAccess();

    if (userId == null || permissionSetGroupId == null) {
      throw new AuraHandledException(
        'User ID and Permission Set Group ID are required.'
      );
    }

    PermissionSetGroup grp = [
      SELECT Id, MasterLabel
      FROM PermissionSetGroup
      WHERE Id = :permissionSetGroupId
      LIMIT 1
    ];

    List<PermissionSetAssignment> existing = [
      SELECT Id
      FROM PermissionSetAssignment
      WHERE
        AssigneeId = :userId
        AND PermissionSetGroupId = :permissionSetGroupId
      LIMIT 1
    ];

    if (!existing.isEmpty()) {
      return new AdminSecurityDataModel.DmlResult(
        true,
        'Permission Set Group is already assigned to this user.',
        existing[0].Id
      );
    }

    PermissionSetAssignment psa = new PermissionSetAssignment(
      AssigneeId = userId,
      PermissionSetGroupId = permissionSetGroupId
    );

    insert psa;
    return new AdminSecurityDataModel.DmlResult(
      true,
      'Permission Set Group "' + grp.MasterLabel + '" successfully assigned.',
      psa.Id
    );
  }

  /**
   * @description Remove a Permission Set Group from a user
   */
  public static AdminSecurityDataModel.DmlResult removePermissionSetGroupFromUser(
    Id userId,
    Id permissionSetGroupId
  ) {
    verifyAdminAccess();

    if (userId == null || permissionSetGroupId == null) {
      throw new AuraHandledException(
        'User ID and Permission Set Group ID are required.'
      );
    }

    List<PermissionSetAssignment> psaList = [
      SELECT Id, PermissionSetGroup.MasterLabel
      FROM PermissionSetAssignment
      WHERE
        AssigneeId = :userId
        AND PermissionSetGroupId = :permissionSetGroupId
      LIMIT 1
    ];

    if (psaList.isEmpty()) {
      return new AdminSecurityDataModel.DmlResult(
        true,
        'Assignment record not found or already removed.'
      );
    }

    String label = psaList[0].PermissionSetGroup != null
      ? psaList[0].PermissionSetGroup.MasterLabel
      : 'Permission Set Group';
    delete psaList;
    return new AdminSecurityDataModel.DmlResult(
      true,
      'Permission Set Group "' + label + '" assignment successfully removed.'
    );
  }

  /**
   * @description Bulk assign users to a permission set
   */
  public static AdminSecurityDataModel.DmlResult assignUsersToPermissionSet(
    Id permissionSetId,
    List<Id> userIds
  ) {
    verifyAdminAccess();

    if (permissionSetId == null || userIds == null || userIds.isEmpty()) {
      throw new AuraHandledException(
        'Permission Set ID and at least one User ID are required.'
      );
    }

    Set<Id> existingUserIds = new Set<Id>();
    for (PermissionSetAssignment psa : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE
        PermissionSetId = :permissionSetId
        AND PermissionSetGroupId = NULL
        AND AssigneeId IN :userIds
    ]) {
      existingUserIds.add(psa.AssigneeId);
    }

    List<PermissionSetAssignment> newAssignments = new List<PermissionSetAssignment>();
    for (Id uId : userIds) {
      if (!existingUserIds.contains(uId)) {
        newAssignments.add(
          new PermissionSetAssignment(
            AssigneeId = uId,
            PermissionSetId = permissionSetId
          )
        );
      }
    }

    if (!newAssignments.isEmpty()) {
      insert newAssignments;
    }

    return new AdminSecurityDataModel.DmlResult(
      true,
      newAssignments.size() + ' user(s) assigned successfully.'
    );
  }

  /**
   * @description Bulk remove users from a permission set
   */
  public static AdminSecurityDataModel.DmlResult removeUsersFromPermissionSet(
    Id permissionSetId,
    List<Id> userIds
  ) {
    verifyAdminAccess();

    if (permissionSetId == null || userIds == null || userIds.isEmpty()) {
      throw new AuraHandledException(
        'Permission Set ID and at least one User ID are required.'
      );
    }

    List<PermissionSetAssignment> toDelete = [
      SELECT Id
      FROM PermissionSetAssignment
      WHERE
        PermissionSetId = :permissionSetId
        AND PermissionSetGroupId = NULL
        AND AssigneeId IN :userIds
    ];

    if (!toDelete.isEmpty()) {
      delete toDelete;
    }

    return new AdminSecurityDataModel.DmlResult(
      true,
      toDelete.size() + ' user assignment(s) removed.'
    );
  }

  /**
   * @description Bulk assign users to a permission set group
   */
  public static AdminSecurityDataModel.DmlResult assignUsersToPermissionSetGroup(
    Id permissionSetGroupId,
    List<Id> userIds
  ) {
    verifyAdminAccess();

    if (permissionSetGroupId == null || userIds == null || userIds.isEmpty()) {
      throw new AuraHandledException(
        'Group ID and at least one User ID are required.'
      );
    }

    Set<Id> existingUserIds = new Set<Id>();
    for (PermissionSetAssignment psa : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE
        PermissionSetGroupId = :permissionSetGroupId
        AND AssigneeId IN :userIds
    ]) {
      existingUserIds.add(psa.AssigneeId);
    }

    List<PermissionSetAssignment> newAssignments = new List<PermissionSetAssignment>();
    for (Id uId : userIds) {
      if (!existingUserIds.contains(uId)) {
        newAssignments.add(
          new PermissionSetAssignment(
            AssigneeId = uId,
            PermissionSetGroupId = permissionSetGroupId
          )
        );
      }
    }

    if (!newAssignments.isEmpty()) {
      insert newAssignments;
    }

    return new AdminSecurityDataModel.DmlResult(
      true,
      newAssignments.size() + ' user(s) assigned to group successfully.'
    );
  }

  /**
   * @description Bulk remove users from a permission set group
   */
  public static AdminSecurityDataModel.DmlResult removeUsersFromPermissionSetGroup(
    Id permissionSetGroupId,
    List<Id> userIds
  ) {
    verifyAdminAccess();

    if (permissionSetGroupId == null || userIds == null || userIds.isEmpty()) {
      throw new AuraHandledException(
        'Group ID and at least one User ID are required.'
      );
    }

    List<PermissionSetAssignment> toDelete = [
      SELECT Id
      FROM PermissionSetAssignment
      WHERE
        PermissionSetGroupId = :permissionSetGroupId
        AND AssigneeId IN :userIds
    ];

    if (!toDelete.isEmpty()) {
      delete toDelete;
    }

    return new AdminSecurityDataModel.DmlResult(
      true,
      toDelete.size() + ' user group assignment(s) removed.'
    );
  }

  /**
   * @description Update or create ObjectPermissions on a CUSTOM Permission Set
   */
  public static AdminSecurityDataModel.DmlResult saveObjectPermissions(
    Id permissionSetId,
    String sobjectType,
    Boolean canRead,
    Boolean canCreate,
    Boolean canEdit,
    Boolean canDelete,
    Boolean canViewAll,
    Boolean canModifyAll
  ) {
    verifyAdminAccess();

    if (permissionSetId == null || String.isBlank(sobjectType)) {
      throw new AuraHandledException(
        'Permission Set ID and Object Type are required.'
      );
    }

    PermissionSet ps = [
      SELECT Id, IsCustom, IsOwnedByProfile
      FROM PermissionSet
      WHERE Id = :permissionSetId
      LIMIT 1
    ];
    if (ps.IsOwnedByProfile || !ps.IsCustom) {
      throw new AuraHandledException(
        'Standard profiles and managed permission sets are Metadata Managed by Salesforce Setup and cannot be modified via standard Apex DML. Please use Salesforce Setup.'
      );
    }

    // Salesforce platform rules: If Create/Edit/Delete/ViewAll/ModifyAll is true, Read MUST be true
    if (canCreate || canEdit || canDelete || canViewAll || canModifyAll) {
      canRead = true;
    }
    if (canModifyAll) {
      canViewAll = true;
      canEdit = true;
      canDelete = true;
    }

    List<ObjectPermissions> existingList = [
      SELECT Id
      FROM ObjectPermissions
      WHERE ParentId = :permissionSetId AND SobjectType = :sobjectType
      LIMIT 1
    ];

    ObjectPermissions op;
    if (!existingList.isEmpty()) {
      op = existingList[0];
    } else {
      op = new ObjectPermissions(
        ParentId = permissionSetId,
        SobjectType = sobjectType
      );
    }

    op.PermissionsRead = canRead;
    op.PermissionsCreate = canCreate;
    op.PermissionsEdit = canEdit;
    op.PermissionsDelete = canDelete;
    op.PermissionsViewAllRecords = canViewAll;
    op.PermissionsModifyAllRecords = canModifyAll;

    upsert op;
    return new AdminSecurityDataModel.DmlResult(
      true,
      'Object permissions for ' + sobjectType + ' updated successfully.',
      op.Id
    );
  }

  /**
   * @description Update or create FieldPermissions on a CUSTOM Permission Set
   */
  public static AdminSecurityDataModel.DmlResult saveFieldPermissions(
    Id permissionSetId,
    String sobjectType,
    String fieldApiName,
    Boolean canRead,
    Boolean canEdit
  ) {
    verifyAdminAccess();

    if (
      permissionSetId == null ||
      String.isBlank(sobjectType) ||
      String.isBlank(fieldApiName)
    ) {
      throw new AuraHandledException(
        'Permission Set ID, Object Type, and Field Name are required.'
      );
    }

    PermissionSet ps = [
      SELECT Id, IsCustom, IsOwnedByProfile
      FROM PermissionSet
      WHERE Id = :permissionSetId
      LIMIT 1
    ];
    if (ps.IsOwnedByProfile || !ps.IsCustom) {
      throw new AuraHandledException(
        'Standard profiles and managed permission sets are Metadata Managed by Salesforce Setup and cannot be modified via standard Apex DML. Please use Salesforce Setup.'
      );
    }

    // Field permission rule: If Edit is true, Read must be true
    if (canEdit) {
      canRead = true;
    }

    // Ensure parent ObjectPermissions has Read = true
    List<ObjectPermissions> existingOp = [
      SELECT Id, PermissionsRead
      FROM ObjectPermissions
      WHERE ParentId = :permissionSetId AND SobjectType = :sobjectType
      LIMIT 1
    ];

    if (existingOp.isEmpty()) {
      ObjectPermissions newOp = new ObjectPermissions(
        ParentId = permissionSetId,
        SobjectType = sobjectType,
        PermissionsRead = true
      );
      insert newOp;
    } else if (!existingOp[0].PermissionsRead && canRead) {
      existingOp[0].PermissionsRead = true;
      update existingOp[0];
    }

    List<FieldPermissions> existingFpList = [
      SELECT Id
      FROM FieldPermissions
      WHERE
        ParentId = :permissionSetId
        AND SobjectType = :sobjectType
        AND Field = :fieldApiName
      LIMIT 1
    ];

    FieldPermissions fp;
    if (!existingFpList.isEmpty()) {
      fp = existingFpList[0];
    } else {
      fp = new FieldPermissions(
        ParentId = permissionSetId,
        SobjectType = sobjectType,
        Field = fieldApiName
      );
    }

    fp.PermissionsRead = canRead;
    fp.PermissionsEdit = canEdit;

    upsert fp;
    return new AdminSecurityDataModel.DmlResult(
      true,
      'Field permissions for ' + fieldApiName + ' updated successfully.',
      fp.Id
    );
  }

  /**
   * @description Toggle active status of a user (with self-deactivation protection)
   */
  public static AdminSecurityDataModel.DmlResult toggleUserActiveStatus(
    Id userId,
    Boolean isActive
  ) {
    verifyAdminAccess();

    if (userId == null) {
      throw new AuraHandledException('User ID cannot be blank.');
    }

    if (userId == UserInfo.getUserId() && !isActive) {
      throw new AuraHandledException(
        'Security Protection: You cannot deactivate your own administrative account.'
      );
    }

    User u = [SELECT Id, Name, IsActive FROM User WHERE Id = :userId LIMIT 1];
    u.IsActive = isActive;
    update u;

    String action = isActive ? 'activated' : 'deactivated';
    return new AdminSecurityDataModel.DmlResult(
      true,
      'User ' + u.Name + ' has been ' + action + ' successfully.',
      u.Id
    );
  }

  /**
   * @description Create a new active user. Locale, timezone, language and email encoding default
   * from the running admin so only identity fields and a profile are required.
   */
  public static AdminSecurityDataModel.DmlResult createUser(
    String firstName,
    String lastName,
    String email,
    String username,
    String alias,
    Id profileId
  ) {
    verifyAdminAccess();
    if (String.isBlank(lastName)) {
      throw new AuraHandledException('Last name is required.');
    }
    if (String.isBlank(email)) {
      throw new AuraHandledException('Email is required.');
    }
    if (profileId == null) {
      throw new AuraHandledException('A profile is required.');
    }

    String uname = (String.isBlank(username) ? email : username).trim();
    if (![SELECT Id FROM User WHERE Username = :uname LIMIT 1].isEmpty()) {
      throw new AuraHandledException(
        'A user with the username "' + uname + '" already exists.'
      );
    }

    String aliasVal = String.isBlank(alias)
      ? deriveAlias(firstName, lastName)
      : alias.trim();
    if (aliasVal.length() > 8) {
      aliasVal = aliasVal.substring(0, 8);
    }

    User u = new User(
      FirstName = String.isBlank(firstName) ? null : firstName.trim(),
      LastName = lastName.trim(),
      Email = email.trim(),
      Username = uname,
      Alias = aliasVal,
      ProfileId = profileId,
      IsActive = true,
      TimeZoneSidKey = UserInfo.getTimeZone().getID(),
      LocaleSidKey = UserInfo.getLocale(),
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = UserInfo.getLanguage()
    );
    insert u;
    return new AdminSecurityDataModel.DmlResult(
      true,
      'User "' + u.LastName + '" created.',
      u.Id
    );
  }

  /** @description Build a valid (<= 8 char) alias from the user's name. */
  private static String deriveAlias(String firstName, String lastName) {
    String first = String.isBlank(firstName) ? '' : firstName.trim();
    String last = String.isBlank(lastName) ? '' : lastName.trim();
    String base = ((first.length() > 0 ? first.substring(0, 1) : '') + last)
      .replaceAll('[^a-zA-Z0-9]', '');
    if (String.isBlank(base)) {
      base = 'user';
    }
    return base.length() > 8 ? base.substring(0, 8) : base;
  }
}