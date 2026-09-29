/**
 * @description Profile- and User-centric access editor for the Admin Access Console.
 * Reads current access and writes changes to:
 *  - Profile: the profile's own (profile-owned) permission set, so changes apply to every user on the profile.
 *  - User: a console-managed personal permission set ("AAC_User_<userId>") that is created and
 *    assigned on first save, so changes apply to that one user only. Access the user already
 *    receives from their profile, permission sets or groups is reported as inherited.
 */
public with sharing class AdminAccessEditorService {

    public static final String TYPE_PROFILE = 'Profile';
    public static final String TYPE_USER = 'User';
    public static final String TYPE_PERMISSION_SET = 'PermissionSet';
    public static final String KIND_PERMISSION_SET = 'PermissionSet';
    public static final String KIND_PERMISSION_SET_GROUP = 'PermissionSetGroup';
    public static final String PERSONAL_PS_PREFIX = 'AAC_User_';

    private static final Set<String> SETUP_ENTITY_TYPES = new Set<String>{ 'TabSet', 'ApexClass', 'FlowDefinition' };
    private static final Integer MAX_ERRORS = 10;

    public class EditorException extends Exception {}

    /**
     * @description Resolved editing target. editPermSetId is the permission set that receives changes;
     * sourceLabels holds every other permission set that grants the target access (users only).
     */
    private class Target {
        String targetType;
        Id targetId;
        String name;
        Id profileId;
        String profileName;
        Boolean isCustomProfile = false;
        Boolean hasModifyAllData = false;
        Id editPermSetId;
        String editPermSetLabel;
        Boolean editPermSetAssigned = false;
        Map<Id, String> sourceLabels = new Map<Id, String>();

        Set<Id> allParentIds() {
            Set<Id> ids = new Set<Id>(sourceLabels.keySet());
            if (editPermSetId != null) {
                ids.add(editPermSetId);
            }
            return ids;
        }

        Boolean canEditObjectAccess() {
            // For a permission set target, isCustomProfile carries the set's IsCustom flag.
            return targetType == TYPE_USER || (isCustomProfile && !hasModifyAllData);
        }
    }

    // =========================================================================
    // TARGET RESOLUTION
    // =========================================================================

    private static Target resolve(String targetType, Id targetId) {
        AdminSecurityService.verifyAdminAccess();
        if (targetId == null) {
            throw new EditorException('Select a profile or user first.');
        }

        Target t = new Target();
        t.targetId = targetId;
        t.targetType = targetType;

        if (targetType == TYPE_PROFILE) {
            List<PermissionSet> psList = [
                SELECT Id, IsCustom, PermissionsModifyAllData, ProfileId, Profile.Name
                FROM PermissionSet
                WHERE IsOwnedByProfile = true AND ProfileId = :targetId
                LIMIT 1
            ];
            if (psList.isEmpty()) {
                throw new EditorException('No underlying permission set was found for this profile.');
            }
            PermissionSet ps = psList[0];
            t.name = ps.Profile.Name;
            t.profileId = ps.ProfileId;
            t.profileName = ps.Profile.Name;
            t.isCustomProfile = ps.IsCustom;
            t.hasModifyAllData = ps.PermissionsModifyAllData;
            t.editPermSetId = ps.Id;
            t.editPermSetLabel = 'Profile: ' + ps.Profile.Name;
            t.editPermSetAssigned = true;
        } else if (targetType == TYPE_PERMISSION_SET) {
            List<PermissionSet> psList = [
                SELECT Id, Name, Label, IsCustom, IsOwnedByProfile, PermissionsModifyAllData
                FROM PermissionSet
                WHERE Id = :targetId
                LIMIT 1
            ];
            if (psList.isEmpty()) {
                throw new EditorException('Permission set not found.');
            }
            PermissionSet ps = psList[0];
            if (ps.IsOwnedByProfile) {
                throw new EditorException('This permission set belongs to a profile. Edit the profile instead.');
            }
            t.name = ps.Label;
            t.isCustomProfile = ps.IsCustom; // reused as "is custom / editable"
            t.hasModifyAllData = ps.PermissionsModifyAllData;
            t.editPermSetId = ps.Id;
            t.editPermSetLabel = ps.Label;
            t.editPermSetAssigned = true;
        } else if (targetType == TYPE_USER) {
            User u = [SELECT Id, Name, ProfileId, Profile.Name FROM User WHERE Id = :targetId LIMIT 1];
            t.name = u.Name;
            t.profileId = u.ProfileId;
            t.profileName = u.Profile != null ? u.Profile.Name : null;
            String personalName = personalPermSetName(u.Id);

            for (PermissionSetAssignment psa : [
                SELECT PermissionSetId, PermissionSet.Name, PermissionSet.Label, PermissionSet.IsOwnedByProfile,
                       PermissionSet.IsCustom, PermissionSet.PermissionsModifyAllData,
                       PermissionSetGroupId, PermissionSetGroup.MasterLabel
                FROM PermissionSetAssignment
                WHERE AssigneeId = :u.Id
            ]) {
                if (psa.PermissionSet.Name == personalName) {
                    t.editPermSetId = psa.PermissionSetId;
                    t.editPermSetLabel = psa.PermissionSet.Label;
                    t.editPermSetAssigned = true;
                    continue;
                }
                String label;
                if (psa.PermissionSet.IsOwnedByProfile) {
                    label = 'Profile: ' + t.profileName;
                    t.isCustomProfile = psa.PermissionSet.IsCustom;
                } else if (psa.PermissionSetGroupId != null) {
                    label = 'Group: ' + psa.PermissionSetGroup.MasterLabel;
                } else {
                    label = psa.PermissionSet.Label;
                }
                t.sourceLabels.put(psa.PermissionSetId, label);
                if (psa.PermissionSet.PermissionsModifyAllData) {
                    t.hasModifyAllData = true;
                }
            }

            if (t.editPermSetId == null) {
                List<PermissionSet> existing = [SELECT Id, Label FROM PermissionSet WHERE Name = :personalName LIMIT 1];
                if (!existing.isEmpty()) {
                    t.editPermSetId = existing[0].Id;
                    t.editPermSetLabel = existing[0].Label;
                } else {
                    t.editPermSetLabel = personalPermSetLabel(u.Name);
                }
            }
        } else {
            throw new EditorException('Unsupported target type: ' + targetType);
        }
        return t;
    }

    public static String personalPermSetName(Id userId) {
        return PERSONAL_PS_PREFIX + String.valueOf(userId);
    }

    private static String personalPermSetLabel(String userName) {
        return ('Admin Access - ' + userName).abbreviate(80);
    }

    /**
     * @description For users, create (if needed) and assign the personal permission set that holds console edits.
     */
    private static void ensureEditPermSet(Target t) {
        if (t.targetType != TYPE_USER) {
            return;
        }
        if (t.editPermSetId == null) {
            PermissionSet ps = new PermissionSet(
                Name = personalPermSetName(t.targetId),
                Label = t.editPermSetLabel,
                Description = 'Managed by the Admin Access Console. Holds access granted directly to ' + t.name + '.'
            );
            insert ps;
            t.editPermSetId = ps.Id;
        }
        if (!t.editPermSetAssigned) {
            insert new PermissionSetAssignment(AssigneeId = t.targetId, PermissionSetId = t.editPermSetId);
            t.editPermSetAssigned = true;
        }
    }

    private static String joinSources(Set<Id> parentIds, Target t) {
        List<String> labels = new List<String>();
        for (Id pid : parentIds) {
            if (pid == t.editPermSetId) {
                labels.add(t.targetType == TYPE_USER ? 'Direct (this console)' : t.editPermSetLabel);
            } else if (t.sourceLabels.containsKey(pid)) {
                labels.add(t.sourceLabels.get(pid));
            }
        }
        labels.sort();
        return String.join(labels, ', ');
    }

    // =========================================================================
    // CONTEXT
    // =========================================================================

    public static AdminSecurityDataModel.AccessContext getAccessContext(String targetType, Id targetId) {
        Target t = resolve(targetType, targetId);

        AdminSecurityDataModel.AccessContext ctx = new AdminSecurityDataModel.AccessContext();
        ctx.targetType = t.targetType;
        ctx.targetId = t.targetId;
        ctx.name = t.name;
        ctx.profileId = t.profileId;
        ctx.profileName = t.profileName;
        ctx.isCustomProfile = t.isCustomProfile;
        ctx.hasModifyAllData = t.hasModifyAllData;
        ctx.editPermSetId = t.editPermSetId;
        ctx.editPermSetLabel = t.editPermSetLabel;
        ctx.editPermSetExists = t.editPermSetId != null;
        ctx.canEditObjectAccess = t.canEditObjectAccess();
        ctx.canEditSetupAccess = true;

        if (t.targetType == TYPE_PROFILE) {
            ctx.setupUrl = '/lightning/setup/EnhancedProfiles/page?address=%2F' + t.targetId;
            if (!t.isCustomProfile) {
                ctx.readOnlyReason = 'Standard profiles do not allow object and field permission changes. Clone the profile in Setup, or grant access to individual users with a permission set.';
            } else if (t.hasModifyAllData) {
                ctx.readOnlyReason = 'This profile has "Modify All Data", which already grants full object and field access.';
            }

            AdminSecurityDataModel.ProfileDetail detail = AdminSecurityService.getProfileDetail(t.targetId);
            ctx.users = detail.associatedUsers;
            ctx.systemPermissions = detail.systemPermissions;
            ctx.activeUserCount = [SELECT count() FROM User WHERE ProfileId = :t.targetId AND IsActive = true];
        } else if (t.targetType == TYPE_PERMISSION_SET) {
            ctx.setupUrl = '/lightning/setup/PermSets/page?address=%2F' + t.targetId;
            ctx.activeUserCount = [
                SELECT count() FROM PermissionSetAssignment
                WHERE PermissionSetId = :t.targetId AND PermissionSetGroupId = null
            ];
            if (!t.isCustomProfile) {
                ctx.readOnlyReason = 'This is a managed (installed) permission set. Its object and field permissions are controlled by the package and cannot be changed here.';
            } else if (t.hasModifyAllData) {
                ctx.readOnlyReason = 'This permission set has "Modify All Data", which already grants full object and field access.';
            }
        } else {
            ctx.setupUrl = '/lightning/setup/ManageUsers/page?address=%2F' + t.targetId + '%3Fnoredirect%3D1';
            ctx.activeUserCount = 1;
            if (t.hasModifyAllData) {
                ctx.readOnlyReason = 'This user has "Modify All Data", so every object and field is already accessible.';
            }
        }
        return ctx;
    }

    // =========================================================================
    // PERMISSION SET / PERMISSION SET GROUP ASSIGNMENTS
    // =========================================================================

    public static List<AdminSecurityDataModel.AssignmentItem> getAssignments(String targetType, Id targetId, String kind) {
        Target t = resolve(targetType, targetId);
        Boolean isUser = t.targetType == TYPE_USER;

        Integer total = isUser ? 1 : [SELECT count() FROM User WHERE ProfileId = :t.profileId AND IsActive = true];
        Map<Id, Integer> counts = new Map<Id, Integer>();
        List<AdminSecurityDataModel.AssignmentItem> items = new List<AdminSecurityDataModel.AssignmentItem>();

        if (kind == KIND_PERMISSION_SET) {
            List<AggregateResult> rows = isUser
                ? [SELECT PermissionSetId k, COUNT(Id) c FROM PermissionSetAssignment
                   WHERE AssigneeId = :t.targetId AND PermissionSetGroupId = null AND PermissionSet.IsOwnedByProfile = false
                   GROUP BY PermissionSetId]
                : [SELECT PermissionSetId k, COUNT(Id) c FROM PermissionSetAssignment
                   WHERE Assignee.ProfileId = :t.profileId AND Assignee.IsActive = true
                   AND PermissionSetGroupId = null AND PermissionSet.IsOwnedByProfile = false
                   GROUP BY PermissionSetId];
            for (AggregateResult ar : rows) {
                counts.put((Id) ar.get('k'), (Integer) ar.get('c'));
            }

            String ownPersonal = isUser ? personalPermSetName(t.targetId) : null;
            for (PermissionSet ps : [
                SELECT Id, Name, Label, Description, IsCustom, NamespacePrefix, License.Name
                FROM PermissionSet
                WHERE IsOwnedByProfile = false AND PermissionSetGroupId = null
                ORDER BY Label ASC
                LIMIT 1000
            ]) {
                Boolean isPersonal = ps.Name.startsWith(PERSONAL_PS_PREFIX);
                if (isPersonal && ps.Name != ownPersonal) {
                    continue;
                }
                AdminSecurityDataModel.AssignmentItem item = new AdminSecurityDataModel.AssignmentItem();
                item.id = ps.Id;
                item.label = ps.Label;
                item.apiName = String.isBlank(ps.NamespacePrefix) ? ps.Name : ps.NamespacePrefix + '__' + ps.Name;
                item.description = ps.Description;
                item.typeLabel = isPersonal ? 'Console managed' : (ps.IsCustom ? 'Custom' : 'Standard');
                item.status = ps.License != null ? ps.License.Name : 'No license';
                item.assignedCount = counts.containsKey(ps.Id) ? counts.get(ps.Id) : 0;
                item.totalCount = total;
                item.isAssigned = item.assignedCount > 0;
                items.add(item);
            }
        } else if (kind == KIND_PERMISSION_SET_GROUP) {
            List<AggregateResult> rows = isUser
                ? [SELECT PermissionSetGroupId k, COUNT(Id) c FROM PermissionSetAssignment
                   WHERE AssigneeId = :t.targetId AND PermissionSetGroupId != null
                   GROUP BY PermissionSetGroupId]
                : [SELECT PermissionSetGroupId k, COUNT(Id) c FROM PermissionSetAssignment
                   WHERE Assignee.ProfileId = :t.profileId AND Assignee.IsActive = true AND PermissionSetGroupId != null
                   GROUP BY PermissionSetGroupId];
            for (AggregateResult ar : rows) {
                counts.put((Id) ar.get('k'), (Integer) ar.get('c'));
            }

            for (PermissionSetGroup grp : [
                SELECT Id, DeveloperName, MasterLabel, Description, Status, NamespacePrefix
                FROM PermissionSetGroup
                ORDER BY MasterLabel ASC
                LIMIT 1000
            ]) {
                AdminSecurityDataModel.AssignmentItem item = new AdminSecurityDataModel.AssignmentItem();
                item.id = grp.Id;
                item.label = grp.MasterLabel;
                item.apiName = String.isBlank(grp.NamespacePrefix) ? grp.DeveloperName : grp.NamespacePrefix + '__' + grp.DeveloperName;
                item.description = grp.Description;
                item.typeLabel = String.isBlank(grp.NamespacePrefix) ? 'Custom' : 'Managed';
                item.status = grp.Status;
                item.assignedCount = counts.containsKey(grp.Id) ? counts.get(grp.Id) : 0;
                item.totalCount = total;
                item.isAssigned = item.assignedCount > 0;
                items.add(item);
            }
        } else {
            throw new EditorException('Unsupported assignment type: ' + kind);
        }

        items.sort();
        return items;
    }

    /**
     * @description Assign or remove a permission set / group. For a profile, this applies to every active user on it.
     */
    public static AdminSecurityDataModel.DmlResult setAssignment(String targetType, Id targetId, String kind, Id itemId, Boolean assign) {
        Target t = resolve(targetType, targetId);
        if (itemId == null) {
            throw new EditorException('Select a permission set or group.');
        }
        Boolean isGroup = kind == KIND_PERMISSION_SET_GROUP;
        if (!isGroup && kind != KIND_PERMISSION_SET) {
            throw new EditorException('Unsupported assignment type: ' + kind);
        }

        if (t.targetType == TYPE_USER) {
            if (isGroup) {
                return assign
                    ? AdminSecurityService.assignPermissionSetGroupToUser(t.targetId, itemId)
                    : AdminSecurityService.removePermissionSetGroupFromUser(t.targetId, itemId);
            }
            return assign
                ? AdminSecurityService.assignPermissionSetToUser(t.targetId, itemId)
                : AdminSecurityService.removePermissionSetFromUser(t.targetId, itemId);
        }

        // Profile: bulk apply to active users on the profile
        List<PermissionSetAssignment> existing = isGroup
            ? [SELECT Id, AssigneeId FROM PermissionSetAssignment
               WHERE PermissionSetGroupId = :itemId AND Assignee.ProfileId = :t.profileId AND Assignee.IsActive = true]
            : [SELECT Id, AssigneeId FROM PermissionSetAssignment
               WHERE PermissionSetId = :itemId AND PermissionSetGroupId = null
               AND Assignee.ProfileId = :t.profileId AND Assignee.IsActive = true];

        List<String> errors = new List<String>();
        Integer applied = 0;

        if (assign) {
            Set<Id> alreadyAssigned = new Set<Id>();
            for (PermissionSetAssignment psa : existing) {
                alreadyAssigned.add(psa.AssigneeId);
            }
            List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
            List<String> keys = new List<String>();
            for (User u : [SELECT Id, Name FROM User WHERE ProfileId = :t.profileId AND IsActive = true LIMIT 5000]) {
                if (alreadyAssigned.contains(u.Id)) {
                    continue;
                }
                toInsert.add(isGroup
                    ? new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetGroupId = itemId)
                    : new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = itemId));
                keys.add(u.Name);
            }
            applied = collectSaveErrors(Database.insert(toInsert, false), keys, errors);
            return buildResult(applied, errors, applied + ' user(s) on ' + t.name + ' assigned.');
        }

        List<String> keys = new List<String>();
        for (PermissionSetAssignment psa : existing) {
            keys.add(String.valueOf(psa.AssigneeId));
        }
        applied = collectDeleteErrors(Database.delete(existing, false), keys, errors);
        return buildResult(applied, errors, applied + ' user assignment(s) on ' + t.name + ' removed.');
    }

    // =========================================================================
    // SETUP ENTITY ACCESS: APPS (TabSet), APEX CLASSES, FLOWS
    // =========================================================================

    public static List<AdminSecurityDataModel.EntityAccessItem> getEntityAccess(String targetType, Id targetId, String entityType) {
        Target t = resolve(targetType, targetId);
        if (!SETUP_ENTITY_TYPES.contains(entityType)) {
            throw new EditorException('Unsupported access type: ' + entityType);
        }

        Map<Id, AdminSecurityDataModel.EntityAccessItem> catalog = new Map<Id, AdminSecurityDataModel.EntityAccessItem>();
        if (entityType == 'TabSet') {
            for (AppMenuItem app : [
                SELECT ApplicationId, Name, Label, Description, NamespacePrefix
                FROM AppMenuItem
                WHERE Type = 'TabSet' AND ApplicationId != null
                LIMIT 1000
            ]) {
                catalog.put(app.ApplicationId, newEntity(app.ApplicationId, app.Label, app.Name,
                    String.isBlank(app.NamespacePrefix) ? 'App' : 'Managed (' + app.NamespacePrefix + ')', app.Description));
            }
        } else if (entityType == 'ApexClass') {
            for (ApexClass cls : [
                SELECT Id, Name, NamespacePrefix, ApiVersion
                FROM ApexClass
                WHERE Status = 'Active'
                ORDER BY NamespacePrefix NULLS FIRST, Name ASC
                LIMIT 3000
            ]) {
                String apiName = String.isBlank(cls.NamespacePrefix) ? cls.Name : cls.NamespacePrefix + '.' + cls.Name;
                catalog.put(cls.Id, newEntity(cls.Id, cls.Name, apiName,
                    String.isBlank(cls.NamespacePrefix) ? 'Custom' : 'Managed (' + cls.NamespacePrefix + ')',
                    'API ' + cls.ApiVersion));
            }
        } else {
            for (FlowDefinitionView fd : [
                SELECT DurableId, ApiName, Label, ProcessType, IsActive, Description
                FROM FlowDefinitionView
                LIMIT 2000
            ]) {
                // Salesforce-provided flows report a non-Id DurableId and cannot be granted through SetupEntityAccess.
                if (fd.DurableId == null || !fd.DurableId.startsWith('300')) {
                    continue;
                }
                catalog.put(fd.DurableId, newEntity(fd.DurableId, fd.Label, fd.ApiName,
                    flowTypeLabel(fd.ProcessType) + (fd.IsActive ? '' : ' (Inactive)'), fd.Description));
            }
        }

        Map<Id, Set<Id>> grantsByEntity = new Map<Id, Set<Id>>();
        Set<Id> parentIds = t.allParentIds();
        if (!parentIds.isEmpty() && !catalog.isEmpty()) {
            Set<Id> entityIds = catalog.keySet();
            for (SetupEntityAccess sea : [
                SELECT ParentId, SetupEntityId
                FROM SetupEntityAccess
                WHERE SetupEntityType = :entityType AND ParentId IN :parentIds AND SetupEntityId IN :entityIds
            ]) {
                if (!grantsByEntity.containsKey(sea.SetupEntityId)) {
                    grantsByEntity.put(sea.SetupEntityId, new Set<Id>());
                }
                grantsByEntity.get(sea.SetupEntityId).add(sea.ParentId);
            }
        }

        List<AdminSecurityDataModel.EntityAccessItem> items = catalog.values();
        for (AdminSecurityDataModel.EntityAccessItem item : items) {
            Set<Id> grants = grantsByEntity.get(item.id);
            if (grants == null) {
                continue;
            }
            item.isEnabled = t.editPermSetId != null && grants.contains(t.editPermSetId);
            Set<Id> others = new Set<Id>(grants);
            others.remove(t.editPermSetId);
            item.isInherited = !others.isEmpty();
            item.sources = joinSources(grants, t);
        }
        items.sort();
        return items;
    }

    public static AdminSecurityDataModel.DmlResult saveEntityAccess(String targetType, Id targetId, String entityType, String changesJson) {
        Target t = resolve(targetType, targetId);
        if (!SETUP_ENTITY_TYPES.contains(entityType)) {
            throw new EditorException('Unsupported access type: ' + entityType);
        }
        List<AdminSecurityDataModel.EntityAccessChange> changes = (List<AdminSecurityDataModel.EntityAccessChange>)
            JSON.deserialize(String.isBlank(changesJson) ? '[]' : changesJson, List<AdminSecurityDataModel.EntityAccessChange>.class);
        if (changes.isEmpty()) {
            return new AdminSecurityDataModel.DmlResult(true, 'No changes to save.');
        }

        ensureEditPermSet(t);

        Set<Id> entityIds = new Set<Id>();
        for (AdminSecurityDataModel.EntityAccessChange c : changes) {
            entityIds.add(Id.valueOf(c.id));
        }
        Map<Id, SetupEntityAccess> existing = new Map<Id, SetupEntityAccess>();
        for (SetupEntityAccess sea : [
            SELECT Id, SetupEntityId FROM SetupEntityAccess
            WHERE ParentId = :t.editPermSetId AND SetupEntityId IN :entityIds
        ]) {
            existing.put(sea.SetupEntityId, sea);
        }

        List<SetupEntityAccess> toInsert = new List<SetupEntityAccess>();
        List<String> insertKeys = new List<String>();
        List<SetupEntityAccess> toDelete = new List<SetupEntityAccess>();
        List<String> deleteKeys = new List<String>();
        for (AdminSecurityDataModel.EntityAccessChange c : changes) {
            Id entityId = Id.valueOf(c.id);
            if (c.enabled == true && !existing.containsKey(entityId)) {
                toInsert.add(new SetupEntityAccess(ParentId = t.editPermSetId, SetupEntityId = entityId));
                insertKeys.add(c.id);
            } else if (c.enabled != true && existing.containsKey(entityId)) {
                toDelete.add(existing.get(entityId));
                deleteKeys.add(c.id);
            }
        }

        List<String> errors = new List<String>();
        Integer applied = collectSaveErrors(Database.insert(toInsert, false), insertKeys, errors)
                        + collectDeleteErrors(Database.delete(toDelete, false), deleteKeys, errors);
        return buildResult(applied, errors, applied + ' access change(s) saved to ' + t.editPermSetLabel + '.');
    }

    // =========================================================================
    // OBJECT PERMISSIONS
    // =========================================================================

    /**
     * @description Objects that support object permissions and exist in this org (the picklist also
     * lists entities for features that are not enabled, so it is intersected with the global describe).
     */
    private static Map<String, String> permissionableObjects() {
        Set<String> available = Schema.getGlobalDescribe().keySet();
        Map<String, String> result = new Map<String, String>();
        for (Schema.PicklistEntry pe : ObjectPermissions.SobjectType.getDescribe().getPicklistValues()) {
            if (available.contains(pe.getValue().toLowerCase())) {
                result.put(pe.getValue(), pe.getLabel());
            }
        }
        return result;
    }

    public static List<AdminSecurityDataModel.ObjectAccessItem> getObjectAccess(String targetType, Id targetId) {
        Target t = resolve(targetType, targetId);
        Map<String, String> objects = permissionableObjects();

        Map<String, AdminSecurityDataModel.ObjectAccessItem> byObject = new Map<String, AdminSecurityDataModel.ObjectAccessItem>();
        for (String sobjectType : objects.keySet()) {
            AdminSecurityDataModel.ObjectAccessItem item = new AdminSecurityDataModel.ObjectAccessItem();
            item.sobjectType = sobjectType;
            item.label = objects.get(sobjectType);
            item.isCustom = sobjectType.endsWith('__c');
            item.canRead = false;
            item.canCreate = false;
            item.canEdit = false;
            item.canDelete = false;
            item.canViewAll = false;
            item.canModifyAll = false;
            item.inhRead = false;
            item.inhCreate = false;
            item.inhEdit = false;
            item.inhDelete = false;
            item.inhViewAll = false;
            item.inhModifyAll = false;
            byObject.put(sobjectType, item);
        }

        Set<Id> parentIds = t.allParentIds();
        Map<String, Set<Id>> sourcesByObject = new Map<String, Set<Id>>();
        if (!parentIds.isEmpty()) {
            for (ObjectPermissions op : [
                SELECT ParentId, SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit,
                       PermissionsDelete, PermissionsViewAllRecords, PermissionsModifyAllRecords
                FROM ObjectPermissions
                WHERE ParentId IN :parentIds
            ]) {
                AdminSecurityDataModel.ObjectAccessItem item = byObject.get(op.SobjectType);
                if (item == null) {
                    continue;
                }
                if (op.ParentId == t.editPermSetId) {
                    item.canRead = op.PermissionsRead;
                    item.canCreate = op.PermissionsCreate;
                    item.canEdit = op.PermissionsEdit;
                    item.canDelete = op.PermissionsDelete;
                    item.canViewAll = op.PermissionsViewAllRecords;
                    item.canModifyAll = op.PermissionsModifyAllRecords;
                } else {
                    item.inhRead |= op.PermissionsRead;
                    item.inhCreate |= op.PermissionsCreate;
                    item.inhEdit |= op.PermissionsEdit;
                    item.inhDelete |= op.PermissionsDelete;
                    item.inhViewAll |= op.PermissionsViewAllRecords;
                    item.inhModifyAll |= op.PermissionsModifyAllRecords;
                }
                if (!sourcesByObject.containsKey(op.SobjectType)) {
                    sourcesByObject.put(op.SobjectType, new Set<Id>());
                }
                sourcesByObject.get(op.SobjectType).add(op.ParentId);
            }
        }

        List<AdminSecurityDataModel.ObjectAccessItem> items = byObject.values();
        for (AdminSecurityDataModel.ObjectAccessItem item : items) {
            if (sourcesByObject.containsKey(item.sobjectType)) {
                item.sources = joinSources(sourcesByObject.get(item.sobjectType), t);
            }
        }
        items.sort();
        return items;
    }

    public static AdminSecurityDataModel.DmlResult saveObjectAccess(String targetType, Id targetId, String changesJson) {
        Target t = resolve(targetType, targetId);
        if (!t.canEditObjectAccess()) {
            throw new EditorException('Object permissions on this profile cannot be changed from here.');
        }
        List<AdminSecurityDataModel.ObjectAccessChange> changes = (List<AdminSecurityDataModel.ObjectAccessChange>)
            JSON.deserialize(String.isBlank(changesJson) ? '[]' : changesJson, List<AdminSecurityDataModel.ObjectAccessChange>.class);
        if (changes.isEmpty()) {
            return new AdminSecurityDataModel.DmlResult(true, 'No changes to save.');
        }

        ensureEditPermSet(t);

        Set<String> sobjectTypes = new Set<String>();
        for (AdminSecurityDataModel.ObjectAccessChange c : changes) {
            sobjectTypes.add(c.sobjectType);
        }
        Map<String, ObjectPermissions> existing = new Map<String, ObjectPermissions>();
        for (ObjectPermissions op : [
            SELECT Id, SobjectType FROM ObjectPermissions
            WHERE ParentId = :t.editPermSetId AND SobjectType IN :sobjectTypes
        ]) {
            existing.put(op.SobjectType, op);
        }

        List<ObjectPermissions> toUpsert = new List<ObjectPermissions>();
        List<String> keys = new List<String>();
        for (AdminSecurityDataModel.ObjectAccessChange c : changes) {
            Boolean modifyAll = c.canModifyAll == true;
            Boolean viewAll = modifyAll || c.canViewAll == true;
            Boolean del = modifyAll || c.canDelete == true;
            Boolean edit = del || c.canEdit == true;
            Boolean create = c.canCreate == true;
            Boolean read = viewAll || edit || create || c.canRead == true;

            ObjectPermissions op = existing.containsKey(c.sobjectType)
                ? existing.get(c.sobjectType)
                : new ObjectPermissions(ParentId = t.editPermSetId, SobjectType = c.sobjectType);
            if (op.Id == null && !read) {
                continue; // nothing granted and nothing to revoke
            }
            // Setting every flag to false removes the object permission record.
            op.PermissionsRead = read;
            op.PermissionsCreate = create;
            op.PermissionsEdit = edit;
            op.PermissionsDelete = del;
            op.PermissionsViewAllRecords = viewAll;
            op.PermissionsModifyAllRecords = modifyAll;
            toUpsert.add(op);
            keys.add(c.sobjectType);
        }

        List<String> errors = new List<String>();
        Integer applied = collectUpsertErrors(Database.upsert(toUpsert, false), keys, errors);
        return buildResult(applied, errors, applied + ' object permission change(s) saved to ' + t.editPermSetLabel + '.');
    }

    // =========================================================================
    // FIELD-LEVEL SECURITY
    // =========================================================================

    public static List<AdminSecurityDataModel.FieldAccessItem> getFieldAccess(String targetType, Id targetId, String sobjectType) {
        Target t = resolve(targetType, targetId);
        if (String.isBlank(sobjectType)) {
            throw new EditorException('Select an object.');
        }
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(sobjectType.toLowerCase());
        if (objType == null) {
            throw new EditorException('Object not found: ' + sobjectType);
        }
        Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
        String objName = objDescribe.getName();

        Map<String, AdminSecurityDataModel.FieldAccessItem> byField = new Map<String, AdminSecurityDataModel.FieldAccessItem>();
        for (Schema.SObjectField f : objDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fd = f.getDescribe();
            if (!fd.isPermissionable()) {
                continue;
            }
            AdminSecurityDataModel.FieldAccessItem item = new AdminSecurityDataModel.FieldAccessItem();
            item.field = objName + '.' + fd.getName();
            item.apiName = fd.getName();
            item.label = fd.getLabel();
            item.dataType = String.valueOf(fd.getType());
            item.isCustom = fd.isCustom();
            item.isEditSupported = !fd.isCalculated() && !fd.isAutoNumber();
            item.canRead = false;
            item.canEdit = false;
            item.inhRead = false;
            item.inhEdit = false;
            byField.put(item.field.toLowerCase(), item);
        }

        Set<Id> parentIds = t.allParentIds();
        Map<String, Set<Id>> sourcesByField = new Map<String, Set<Id>>();
        if (!parentIds.isEmpty()) {
            for (FieldPermissions fp : [
                SELECT ParentId, Field, PermissionsRead, PermissionsEdit
                FROM FieldPermissions
                WHERE ParentId IN :parentIds AND SobjectType = :objName
            ]) {
                String key = fp.Field.toLowerCase();
                AdminSecurityDataModel.FieldAccessItem item = byField.get(key);
                if (item == null) {
                    continue;
                }
                if (fp.ParentId == t.editPermSetId) {
                    item.canRead = fp.PermissionsRead;
                    item.canEdit = fp.PermissionsEdit;
                } else {
                    item.inhRead |= fp.PermissionsRead;
                    item.inhEdit |= fp.PermissionsEdit;
                }
                if (!sourcesByField.containsKey(key)) {
                    sourcesByField.put(key, new Set<Id>());
                }
                sourcesByField.get(key).add(fp.ParentId);
            }
        }

        List<AdminSecurityDataModel.FieldAccessItem> items = byField.values();
        for (AdminSecurityDataModel.FieldAccessItem item : items) {
            String key = item.field.toLowerCase();
            if (sourcesByField.containsKey(key)) {
                item.sources = joinSources(sourcesByField.get(key), t);
            }
        }
        items.sort();
        return items;
    }

    public static AdminSecurityDataModel.DmlResult saveFieldAccess(String targetType, Id targetId, String sobjectType, String changesJson) {
        Target t = resolve(targetType, targetId);
        if (!t.canEditObjectAccess()) {
            throw new EditorException('Field permissions on this profile cannot be changed from here.');
        }
        if (String.isBlank(sobjectType)) {
            throw new EditorException('Select an object.');
        }
        List<AdminSecurityDataModel.FieldAccessChange> changes = (List<AdminSecurityDataModel.FieldAccessChange>)
            JSON.deserialize(String.isBlank(changesJson) ? '[]' : changesJson, List<AdminSecurityDataModel.FieldAccessChange>.class);
        if (changes.isEmpty()) {
            return new AdminSecurityDataModel.DmlResult(true, 'No changes to save.');
        }

        ensureEditPermSet(t);

        Set<String> fieldNames = new Set<String>();
        Boolean anyRead = false;
        for (AdminSecurityDataModel.FieldAccessChange c : changes) {
            fieldNames.add(c.field);
            anyRead |= (c.canRead == true || c.canEdit == true);
        }

        // Field access is only useful with object Read. Add it to the edit target when no other source grants it.
        if (anyRead) {
            ensureObjectRead(t, sobjectType);
        }

        Map<String, FieldPermissions> existing = new Map<String, FieldPermissions>();
        for (FieldPermissions fp : [
            SELECT Id, Field FROM FieldPermissions
            WHERE ParentId = :t.editPermSetId AND SobjectType = :sobjectType AND Field IN :fieldNames
        ]) {
            existing.put(fp.Field.toLowerCase(), fp);
        }

        List<FieldPermissions> toUpsert = new List<FieldPermissions>();
        List<String> upsertKeys = new List<String>();
        List<FieldPermissions> toDelete = new List<FieldPermissions>();
        List<String> deleteKeys = new List<String>();
        for (AdminSecurityDataModel.FieldAccessChange c : changes) {
            Boolean edit = c.canEdit == true;
            Boolean read = edit || c.canRead == true;
            FieldPermissions fp = existing.get(c.field.toLowerCase());
            if (!read) {
                if (fp != null) {
                    toDelete.add(fp);
                    deleteKeys.add(c.field);
                }
                continue;
            }
            if (fp == null) {
                fp = new FieldPermissions(ParentId = t.editPermSetId, SobjectType = sobjectType, Field = c.field);
            }
            fp.PermissionsRead = read;
            fp.PermissionsEdit = edit;
            toUpsert.add(fp);
            upsertKeys.add(c.field);
        }

        List<String> errors = new List<String>();
        Integer applied = collectUpsertErrors(Database.upsert(toUpsert, false), upsertKeys, errors)
                        + collectDeleteErrors(Database.delete(toDelete, false), deleteKeys, errors);
        return buildResult(applied, errors, applied + ' field permission change(s) saved to ' + t.editPermSetLabel + '.');
    }

    private static void ensureObjectRead(Target t, String sobjectType) {
        Set<Id> parentIds = t.allParentIds();
        List<ObjectPermissions> granted = [
            SELECT Id, ParentId, PermissionsRead FROM ObjectPermissions
            WHERE ParentId IN :parentIds AND SobjectType = :sobjectType AND PermissionsRead = true
        ];
        if (!granted.isEmpty()) {
            return;
        }
        insert new ObjectPermissions(ParentId = t.editPermSetId, SobjectType = sobjectType, PermissionsRead = true);
    }

    // =========================================================================
    // RECORD TYPES (view only: visibility is profile / permission set metadata, not exposed to Apex DML)
    // =========================================================================

    public static List<AdminSecurityDataModel.RecordTypeItem> getRecordTypes() {
        AdminSecurityService.verifyAdminAccess();
        List<AdminSecurityDataModel.RecordTypeItem> items = new List<AdminSecurityDataModel.RecordTypeItem>();
        for (RecordType rt : [
            SELECT Id, Name, DeveloperName, SobjectType, Description, IsActive
            FROM RecordType
            ORDER BY SobjectType ASC, Name ASC
            LIMIT 2000
        ]) {
            AdminSecurityDataModel.RecordTypeItem item = new AdminSecurityDataModel.RecordTypeItem();
            item.id = rt.Id;
            item.name = rt.Name;
            item.developerName = rt.DeveloperName;
            item.sobjectType = rt.SobjectType;
            item.description = rt.Description;
            item.isActive = rt.IsActive;
            items.add(item);
        }
        return items;
    }

    // =========================================================================
    // USER PROFILE CHANGE
    // =========================================================================

    public static AdminSecurityDataModel.DmlResult changeUserProfile(Id userId, Id profileId) {
        AdminSecurityService.verifyAdminAccess();
        if (userId == null || profileId == null) {
            throw new EditorException('User and profile are required.');
        }
        if (userId == UserInfo.getUserId()) {
            throw new EditorException('You cannot change your own profile from the console.');
        }
        User u = [SELECT Id, Name, ProfileId FROM User WHERE Id = :userId LIMIT 1];
        if (u.ProfileId == profileId) {
            return new AdminSecurityDataModel.DmlResult(true, u.Name + ' already has this profile.', u.Id);
        }
        Profile p = [SELECT Id, Name FROM Profile WHERE Id = :profileId LIMIT 1];
        u.ProfileId = p.Id;
        update u;
        return new AdminSecurityDataModel.DmlResult(true, u.Name + ' now uses the ' + p.Name + ' profile.', u.Id);
    }

    // =========================================================================
    // CREATE PERMISSION SET
    // =========================================================================

    /**
     * @description Create a new, empty custom permission set. Object/field/apex/flow access and user
     * assignments are then configured through the editor with targetType 'PermissionSet'.
     * @param label Display label (required).
     * @param apiName Optional API name; derived from the label when blank.
     * @param licenseId Optional UserLicense Id; null creates a license-free set.
     */
    public static AdminSecurityDataModel.DmlResult createPermissionSet(String label, String apiName, Id licenseId, String description) {
        AdminSecurityService.verifyAdminAccess();
        if (String.isBlank(label)) {
            throw new EditorException('A label is required to create a permission set.');
        }
        String name = sanitizeApiName(String.isBlank(apiName) ? label : apiName);
        if (String.isBlank(name)) {
            throw new EditorException('Could not derive a valid API name. Enter one using letters, numbers and underscores.');
        }
        if (![SELECT Id FROM PermissionSet WHERE Name = :name LIMIT 1].isEmpty()) {
            throw new EditorException('A permission set with the API name "' + name + '" already exists. Choose another name.');
        }

        PermissionSet ps = new PermissionSet(
            Label = label.abbreviate(80),
            Name = name,
            Description = String.isBlank(description) ? null : description.abbreviate(255)
        );
        if (licenseId != null) {
            ps.LicenseId = licenseId;
        }
        insert ps;
        return new AdminSecurityDataModel.DmlResult(true, 'Permission set "' + ps.Label + '" created.', ps.Id);
    }

    /** @description User licenses available for a new permission set, plus a license-free option. */
    public static List<AdminSecurityDataModel.SelectOption> getUserLicenseOptions() {
        AdminSecurityService.verifyAdminAccess();
        List<AdminSecurityDataModel.SelectOption> options = new List<AdminSecurityDataModel.SelectOption>();
        options.add(new AdminSecurityDataModel.SelectOption('None — no user license', ''));
        for (UserLicense ul : [SELECT Id, Name FROM UserLicense ORDER BY Name ASC]) {
            options.add(new AdminSecurityDataModel.SelectOption(ul.Name, ul.Id));
        }
        return options;
    }

    /**
     * @description Turn free text into a valid permission set API name: starts with a letter,
     * only letters/digits/underscores, no doubled or trailing underscores, max 40 chars.
     */
    private static String sanitizeApiName(String raw) {
        String name = raw.trim().replaceAll('[^a-zA-Z0-9]+', '_').replaceAll('_+', '_');
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

    // =========================================================================
    // PERMISSION SET: USER ASSIGNMENTS (Users tab)
    // =========================================================================

    /** @description Active users, each flagged with whether this permission set is assigned to them. */
    public static List<AdminSecurityDataModel.AssignmentItem> getPermSetUsers(Id permSetId) {
        AdminSecurityService.verifyAdminAccess();
        if (permSetId == null) {
            throw new EditorException('Select a permission set first.');
        }

        Set<Id> assignedIds = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId FROM PermissionSetAssignment
            WHERE PermissionSetId = :permSetId AND PermissionSetGroupId = null
        ]) {
            assignedIds.add(psa.AssigneeId);
        }

        List<AdminSecurityDataModel.AssignmentItem> items = new List<AdminSecurityDataModel.AssignmentItem>();
        for (User u : [
            SELECT Id, Name, Username, Email, IsActive, Profile.Name
            FROM User
            WHERE IsActive = true
            ORDER BY Name ASC
            LIMIT 2000
        ]) {
            AdminSecurityDataModel.AssignmentItem item = new AdminSecurityDataModel.AssignmentItem();
            item.id = u.Id;
            item.label = u.Name;
            item.apiName = u.Username;
            item.description = u.Email;
            item.typeLabel = u.Profile != null ? u.Profile.Name : '—';
            item.status = u.IsActive ? 'Active' : 'Inactive';
            item.isAssigned = assignedIds.contains(u.Id);
            item.assignedCount = item.isAssigned ? 1 : 0;
            item.totalCount = 1;
            items.add(item);
        }
        items.sort();
        return items;
    }

    /** @description Assign or remove this permission set for a single user. */
    public static AdminSecurityDataModel.DmlResult setPermSetUser(Id permSetId, Id userId, Boolean assign) {
        AdminSecurityService.verifyAdminAccess();
        if (permSetId == null || userId == null) {
            throw new EditorException('A permission set and a user are required.');
        }
        return assign
            ? AdminSecurityService.assignPermissionSetToUser(userId, permSetId)
            : AdminSecurityService.removePermissionSetFromUser(userId, permSetId);
    }

    // =========================================================================
    // HELPERS
    // =========================================================================

    private static AdminSecurityDataModel.EntityAccessItem newEntity(Id id, String label, String apiName, String typeLabel, String description) {
        AdminSecurityDataModel.EntityAccessItem item = new AdminSecurityDataModel.EntityAccessItem();
        item.id = id;
        item.label = String.isBlank(label) ? apiName : label;
        item.apiName = apiName;
        item.typeLabel = typeLabel;
        item.description = description;
        item.isEnabled = false;
        item.isInherited = false;
        return item;
    }

    private static String flowTypeLabel(String processType) {
        switch on processType {
            when 'Flow' { return 'Screen Flow'; }
            when 'AutoLaunchedFlow' { return 'Autolaunched Flow'; }
            when 'Workflow' { return 'Process Builder'; }
            when 'CustomEvent' { return 'Platform Event Process'; }
            when else { return processType; }
        }
    }

    private static Integer collectSaveErrors(List<Database.SaveResult> results, List<String> keys, List<String> errors) {
        Integer ok = 0;
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                ok++;
            } else {
                addError(errors, keys[i], results[i].getErrors());
            }
        }
        return ok;
    }

    private static Integer collectUpsertErrors(List<Database.UpsertResult> results, List<String> keys, List<String> errors) {
        Integer ok = 0;
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                ok++;
            } else {
                addError(errors, keys[i], results[i].getErrors());
            }
        }
        return ok;
    }

    private static Integer collectDeleteErrors(List<Database.DeleteResult> results, List<String> keys, List<String> errors) {
        Integer ok = 0;
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                ok++;
            } else {
                addError(errors, keys[i], results[i].getErrors());
            }
        }
        return ok;
    }

    private static void addError(List<String> errors, String key, List<Database.Error> dbErrors) {
        if (errors.size() >= MAX_ERRORS) {
            return;
        }
        String message = dbErrors.isEmpty() ? 'Unknown error' : dbErrors[0].getMessage();
        errors.add(key + ': ' + message);
    }

    private static AdminSecurityDataModel.DmlResult buildResult(Integer applied, List<String> errors, String successMessage) {
        AdminSecurityDataModel.DmlResult result;
        if (errors.isEmpty()) {
            result = new AdminSecurityDataModel.DmlResult(true, successMessage);
        } else {
            result = new AdminSecurityDataModel.DmlResult(false,
                applied + ' change(s) saved, ' + errors.size() + (errors.size() >= MAX_ERRORS ? '+' : '') + ' failed.');
        }
        result.errors = errors;
        return result;
    }
}
