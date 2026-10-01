/**
 * @description Tests for AdminAccessEditorController / AdminAccessEditorService.
 */
@isTest
private class AdminAccessEditorControllerTest {

    private static final String USER_TYPE = AdminAccessEditorService.TYPE_USER;
    private static final String PROFILE_TYPE = AdminAccessEditorService.TYPE_PROFILE;
    private static final String PERMSET_TYPE = AdminAccessEditorService.TYPE_PERMISSION_SET;

    @testSetup
    static void setupTestData() {
        insert new PermissionSet(Name = 'AAC_Editor_Test_PS', Label = 'AAC Editor Test PS');
    }

    private static Id testPermSetId() {
        return [SELECT Id FROM PermissionSet WHERE Name = 'AAC_Editor_Test_PS' LIMIT 1].Id;
    }

    private static Id standardUserProfileId() {
        return [SELECT ProfileId FROM PermissionSet WHERE IsOwnedByProfile = true AND IsCustom = false AND Profile.Name = 'Standard User' LIMIT 1].ProfileId;
    }

    @isTest
    static void testUserContextAndPersonalPermSet() {
        Id userId = UserInfo.getUserId();

        Test.startTest();
        AdminSecurityDataModel.AccessContext ctx = AdminAccessEditorController.getAccessContext(USER_TYPE, userId);
        Assert.areEqual(USER_TYPE, ctx.targetType, 'Target type should be User');
        Assert.isTrue(ctx.canEditObjectAccess, 'Users are always editable through the personal permission set');

        String changes = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{ 'sobjectType' => 'Account', 'canRead' => true, 'canEdit' => true }
        });
        AdminSecurityDataModel.DmlResult res = AdminAccessEditorController.saveObjectAccess(USER_TYPE, userId, changes);
        Test.stopTest();

        Assert.isTrue(res.success, 'Object save should succeed: ' + res.errors);
        PermissionSet personal = [SELECT Id FROM PermissionSet WHERE Name = :AdminAccessEditorService.personalPermSetName(userId)];
        Assert.areEqual(1, [SELECT count() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSetId = :personal.Id],
            'Personal permission set should be assigned to the user');
        ObjectPermissions op = [SELECT PermissionsRead, PermissionsEdit FROM ObjectPermissions WHERE ParentId = :personal.Id AND SobjectType = 'Account'];
        Assert.isTrue(op.PermissionsRead && op.PermissionsEdit, 'Edit implies Read and both should be saved');
    }

    @isTest
    static void testUserObjectAndFieldReads() {
        Id userId = UserInfo.getUserId();
        Test.startTest();
        List<AdminSecurityDataModel.ObjectAccessItem> objects = AdminAccessEditorController.getObjectAccess(USER_TYPE, userId);
        List<AdminSecurityDataModel.FieldAccessItem> fields = AdminAccessEditorController.getFieldAccess(USER_TYPE, userId, 'Account');
        Test.stopTest();

        Assert.isFalse(objects.isEmpty(), 'Permissionable objects should be listed');
        Assert.isFalse(fields.isEmpty(), 'Account should have permissionable fields');
        Boolean checkedTab = false;
        for (AdminSecurityDataModel.ObjectAccessItem item : objects) {
            if (item.hasTab != null) {
                checkedTab = true;
                break;
            }
        }
        Assert.isTrue(checkedTab, 'Objects should have hasTab populated');
    }

    @isTest
    static void testUserFieldSaveAndRevoke() {
        Id userId = UserInfo.getUserId();
        Test.startTest();
        String grant = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{ 'field' => 'Account.Description', 'canRead' => true, 'canEdit' => true }
        });
        AdminSecurityDataModel.DmlResult granted = AdminAccessEditorController.saveFieldAccess(USER_TYPE, userId, 'Account', grant);
        String revoke = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{ 'field' => 'Account.Description', 'canRead' => false, 'canEdit' => false }
        });
        AdminSecurityDataModel.DmlResult revoked = AdminAccessEditorController.saveFieldAccess(USER_TYPE, userId, 'Account', revoke);
        Test.stopTest();

        Assert.isTrue(granted.success, 'Field grant should succeed: ' + granted.errors);
        Assert.isTrue(revoked.success, 'Field revoke should succeed: ' + revoked.errors);
        Id personalId = [SELECT Id FROM PermissionSet WHERE Name = :AdminAccessEditorService.personalPermSetName(userId)].Id;
        Assert.areEqual(0, [SELECT count() FROM FieldPermissions WHERE ParentId = :personalId AND Field = 'Account.Description'],
            'Revoked field permission should be deleted');
    }

    @isTest
    static void testUserEntityAccessToggle() {
        Id userId = UserInfo.getUserId();
        Id classId = [SELECT Id FROM ApexClass WHERE Name = 'AdminAccessEditorController' LIMIT 1].Id;

        Test.startTest();
        List<AdminSecurityDataModel.EntityAccessItem> classes = AdminAccessEditorController.getEntityAccess(USER_TYPE, userId, 'ApexClass');
        AdminSecurityDataModel.DmlResult enabled = AdminAccessEditorController.saveEntityAccess(USER_TYPE, userId, 'ApexClass',
            JSON.serialize(new List<Map<String, Object>>{ new Map<String, Object>{ 'id' => classId, 'enabled' => true } }));
        AdminSecurityDataModel.DmlResult disabled = AdminAccessEditorController.saveEntityAccess(USER_TYPE, userId, 'ApexClass',
            JSON.serialize(new List<Map<String, Object>>{ new Map<String, Object>{ 'id' => classId, 'enabled' => false } }));
        AdminAccessEditorController.getEntityAccess(USER_TYPE, userId, 'TabSet');
        AdminAccessEditorController.getEntityAccess(USER_TYPE, userId, 'FlowDefinition');
        Test.stopTest();

        Assert.isFalse(classes.isEmpty(), 'Apex classes should be listed');
        Assert.isTrue(enabled.success, 'Enable should succeed: ' + enabled.errors);
        Assert.isTrue(disabled.success, 'Disable should succeed: ' + disabled.errors);
    }

    @isTest
    static void testUserAssignments() {
        Id userId = UserInfo.getUserId();
        Id psId = testPermSetId();

        Test.startTest();
        AdminAccessEditorController.setAssignment(USER_TYPE, userId, AdminAccessEditorService.KIND_PERMISSION_SET, psId, true);
        List<AdminSecurityDataModel.AssignmentItem> items = AdminAccessEditorController.getAssignments(USER_TYPE, userId, AdminAccessEditorService.KIND_PERMISSION_SET);
        AdminAccessEditorController.setAssignment(USER_TYPE, userId, AdminAccessEditorService.KIND_PERMISSION_SET, psId, false);
        AdminAccessEditorController.getAssignments(USER_TYPE, userId, AdminAccessEditorService.KIND_PERMISSION_SET_GROUP);
        Test.stopTest();

        Boolean found = false;
        for (AdminSecurityDataModel.AssignmentItem item : items) {
            if (item.id == psId) {
                found = item.isAssigned;
            }
        }
        Assert.isTrue(found, 'Test permission set should be reported as assigned');
        Assert.areEqual(0, [SELECT count() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSetId = :psId],
            'Assignment should be removed');
    }

    @isTest
    static void testProfileBulkAssignments() {
        Id profileId = UserInfo.getProfileId();
        Id psId = testPermSetId();

        Test.startTest();
        AdminSecurityDataModel.DmlResult assigned = AdminAccessEditorController.setAssignment(PROFILE_TYPE, profileId, AdminAccessEditorService.KIND_PERMISSION_SET, psId, true);
        List<AdminSecurityDataModel.AssignmentItem> items = AdminAccessEditorController.getAssignments(PROFILE_TYPE, profileId, AdminAccessEditorService.KIND_PERMISSION_SET);
        AdminSecurityDataModel.DmlResult removed = AdminAccessEditorController.setAssignment(PROFILE_TYPE, profileId, AdminAccessEditorService.KIND_PERMISSION_SET, psId, false);
        AdminAccessEditorController.getAssignments(PROFILE_TYPE, profileId, AdminAccessEditorService.KIND_PERMISSION_SET_GROUP);
        Test.stopTest();

        Assert.isNotNull(assigned, 'Assign result expected');
        Assert.isNotNull(removed, 'Remove result expected');
        Assert.isFalse(items.isEmpty(), 'Permission sets should be listed for the profile');
        Assert.areEqual(0, [SELECT count() FROM PermissionSetAssignment WHERE PermissionSetId = :psId AND Assignee.ProfileId = :profileId],
            'Bulk removal should clear assignments on the profile');
    }

    @isTest
    static void testStandardProfileIsReadOnlyForObjects() {
        Id profileId = standardUserProfileId();

        Test.startTest();
        AdminSecurityDataModel.AccessContext ctx = AdminAccessEditorController.getAccessContext(PROFILE_TYPE, profileId);
        AdminAccessEditorController.getObjectAccess(PROFILE_TYPE, profileId);
        AdminAccessEditorController.getFieldAccess(PROFILE_TYPE, profileId, 'Contact');
        AdminAccessEditorController.getEntityAccess(PROFILE_TYPE, profileId, 'ApexClass');
        Boolean blocked = false;
        try {
            AdminAccessEditorController.saveObjectAccess(PROFILE_TYPE, profileId,
                JSON.serialize(new List<Map<String, Object>>{ new Map<String, Object>{ 'sobjectType' => 'Account', 'canRead' => true } }));
        } catch (AuraHandledException ex) {
            blocked = true;
        }
        Test.stopTest();

        Assert.isFalse(ctx.canEditObjectAccess, 'Standard profiles are read-only for object access');
        Assert.isNotNull(ctx.readOnlyReason, 'A read-only reason should be given');
        Assert.isTrue(blocked, 'Saving object access on a standard profile should be blocked');
    }

    @isTest
    static void testProfileEntityAccess() {
        Id profileId = standardUserProfileId();
        Id classId = [SELECT Id FROM ApexClass WHERE Name = 'AdminAccessEditorService' LIMIT 1].Id;

        Test.startTest();
        AdminSecurityDataModel.DmlResult res = AdminAccessEditorController.saveEntityAccess(PROFILE_TYPE, profileId, 'ApexClass',
            JSON.serialize(new List<Map<String, Object>>{ new Map<String, Object>{ 'id' => classId, 'enabled' => true } }));
        Test.stopTest();

        Assert.isNotNull(res, 'Result expected');
    }

    @isTest
    static void testRecordTypesAndEmptyChanges() {
        Id userId = UserInfo.getUserId();
        Test.startTest();
        List<AdminSecurityDataModel.RecordTypeItem> rts = AdminAccessEditorController.getRecordTypes();
        AdminSecurityDataModel.DmlResult noObj = AdminAccessEditorController.saveObjectAccess(USER_TYPE, userId, '[]');
        AdminSecurityDataModel.DmlResult noFld = AdminAccessEditorController.saveFieldAccess(USER_TYPE, userId, 'Account', '[]');
        AdminSecurityDataModel.DmlResult noEnt = AdminAccessEditorController.saveEntityAccess(USER_TYPE, userId, 'TabSet', '[]');
        Test.stopTest();

        Assert.isNotNull(rts, 'Record type list should not be null');
        Assert.isTrue(noObj.success && noFld.success && noEnt.success, 'Empty change sets are no-ops');
    }

    @isTest
    static void testCreatePermissionSetAndEdit() {
        Test.startTest();
        List<AdminSecurityDataModel.SelectOption> licenses = AdminAccessEditorController.getUserLicenseOptions();
        AdminSecurityDataModel.DmlResult created = AdminAccessEditorController.createPermissionSet(
            'AAC New Set Test', '', null, 'Created by test');
        Test.stopTest();

        Assert.isFalse(licenses.isEmpty(), 'License options should include at least the None entry');
        Assert.isTrue(created.success, 'Permission set creation should succeed');
        Assert.isNotNull(created.recordId, 'A new permission set id should be returned');

        PermissionSet ps = [SELECT Id, Name, Label FROM PermissionSet WHERE Id = :created.recordId];
        Assert.areEqual('AAC_New_Set_Test', ps.Name, 'API name should be derived from the label');

        // The new set is a valid editor target and is editable.
        AdminSecurityDataModel.AccessContext ctx = AdminAccessEditorController.getAccessContext(PERMSET_TYPE, ps.Id);
        Assert.areEqual(PERMSET_TYPE, ctx.targetType, 'Target type should be PermissionSet');
        Assert.isTrue(ctx.canEditObjectAccess, 'A custom permission set should be editable');

        AdminSecurityDataModel.DmlResult objRes = AdminAccessEditorController.saveObjectAccess(PERMSET_TYPE, ps.Id,
            JSON.serialize(new List<Map<String, Object>>{ new Map<String, Object>{ 'sobjectType' => 'Account', 'canRead' => true, 'tabVisibility' => 'DefaultOn' } }));
        Assert.isTrue(objRes.success, 'Object access should save directly to the set: ' + objRes.errors);
        Assert.areEqual(1, [SELECT count() FROM ObjectPermissions WHERE ParentId = :ps.Id AND SobjectType = 'Account'],
            'Object permission should be written to the new permission set');
    }

    @isTest
    static void testPermSetUserAssignment() {
        Id psId = testPermSetId();
        Id userId = UserInfo.getUserId();

        Test.startTest();
        List<AdminSecurityDataModel.AssignmentItem> before = AdminAccessEditorController.getPermSetUsers(psId);
        AdminSecurityDataModel.DmlResult assigned = AdminAccessEditorController.setPermSetUser(psId, userId, true);
        AdminSecurityDataModel.DmlResult removed = AdminAccessEditorController.setPermSetUser(psId, userId, false);
        Test.stopTest();

        Assert.isFalse(before.isEmpty(), 'Active users should be listed for assignment');
        Assert.isTrue(assigned.success, 'Assigning the set to a user should succeed');
        Assert.isTrue(removed.success, 'Removing the set from a user should succeed');
        Assert.areEqual(0, [SELECT count() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSetId = :psId],
            'Assignment should be removed');
    }

    @isTest
    static void testCreatePermissionSetGuards() {
        Integer failures = 0;
        Test.startTest();
        try { AdminAccessEditorController.createPermissionSet('', '', null, null); } catch (AuraHandledException ex) { failures++; }
        // Duplicate API name
        AdminAccessEditorController.createPermissionSet('Dup Set', 'AAC_Dup_Set', null, null);
        try { AdminAccessEditorController.createPermissionSet('Dup Set Two', 'AAC_Dup_Set', null, null); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessEditorController.getPermSetUsers(null); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessEditorController.setPermSetUser(null, UserInfo.getUserId(), true); } catch (AuraHandledException ex) { failures++; }
        Test.stopTest();

        Assert.areEqual(4, failures, 'Invalid create/assign requests should raise AuraHandledException');
    }

    @isTest
    static void testGuardsAndErrors() {
        Id userId = UserInfo.getUserId();
        Integer failures = 0;

        Test.startTest();
        try { AdminAccessEditorController.getAccessContext('Queue', userId); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessEditorController.getAccessContext(USER_TYPE, null); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessEditorController.getEntityAccess(USER_TYPE, userId, 'ApexPage'); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessEditorController.getAssignments(USER_TYPE, userId, 'Queue'); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessEditorController.getFieldAccess(USER_TYPE, userId, 'Not_An_Object__zz'); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessEditorController.changeUserProfile(userId, UserInfo.getProfileId()); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessEditorController.setAssignment(USER_TYPE, userId, AdminAccessEditorService.KIND_PERMISSION_SET, null, true); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessEditorController.saveEntityAccess(USER_TYPE, userId, 'ApexPage', '[]'); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessEditorController.saveFieldAccess(USER_TYPE, userId, '', '[]'); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessEditorController.getObjectAccess(USER_TYPE, null); } catch (AuraHandledException ex) { failures++; }
        Test.stopTest();

        Assert.areEqual(10, failures, 'Every invalid request should raise an AuraHandledException');
    }
}