/**
 * @description Comprehensive test suite for AdminAccessController, AdminSecurityService, and AdminSecurityDataModel.
 */
@isTest
private class AdminAccessControllerTest {

    @testSetup
    static void setupTestData() {
        // Create custom Permission Set for testing
        PermissionSet ps = new PermissionSet(
            Name = 'Test_Admin_Custom_PS',
            Label = 'Test Admin Custom PS',
            Description = 'Custom test permission set for unit tests'
        );
        insert ps;

        // Create ObjectPermissions for Account
        ObjectPermissions op = new ObjectPermissions(
            ParentId = ps.Id,
            SobjectType = 'Account',
            PermissionsRead = true,
            PermissionsCreate = true,
            PermissionsEdit = false,
            PermissionsDelete = false,
            PermissionsViewAllRecords = false,
            PermissionsModifyAllRecords = false
        );
        insert op;
    }

    @isTest
    static void testGetAdminOverview() {
        Test.startTest();
        AdminSecurityDataModel.AdminSecurityOverview overview = AdminAccessController.getAdminOverview();
        Test.stopTest();

        Assert.isNotNull(overview, 'Overview should not be null');
        Assert.isTrue(overview.totalUsers > 0, 'Total users should be greater than zero');
        Assert.isTrue(overview.isAuthorizedAdmin, 'Current user should be authorized admin');
        Assert.isNotNull(overview.currentAdminName, 'Admin name should be populated');
    }

    @isTest
    static void testGetUsers() {
        Test.startTest();
        AdminSecurityDataModel.UserPage page = AdminAccessController.getUsers('', '', 'Active', 1, 15);
        Test.stopTest();

        Assert.isNotNull(page, 'User page should not be null');
        Assert.isTrue(page.totalCount > 0, 'Active users should be counted');
        Assert.isTrue(page.records.size() > 0, 'Active users should be returned');
        Assert.isTrue(page.records.size() <= 15, 'Page should not exceed the page size');
        Assert.isNotNull(page.records[0].name, 'User name should not be blank');
    }

    @isTest
    static void testGetUserDetail() {
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        Test.startTest();
        AdminSecurityDataModel.UserDetailView detail = AdminAccessController.getUserDetail(testUser.Id);
        Test.stopTest();

        Assert.isNotNull(detail, 'User detail should not be null');
        Assert.isNotNull(detail.user, 'User info DTO should be populated');
        Assert.areEqual(testUser.Id, detail.user.userId, 'User ID should match');
        Assert.isNotNull(detail.assignedPermissionSets, 'Assigned permission sets list should not be null');
        Assert.isNotNull(detail.availablePermissionSets, 'Available permission sets list should not be null');
    }

    @isTest
    static void testGetPermissionSets() {
        Test.startTest();
        AdminSecurityDataModel.PermissionSetPage allPs = AdminAccessController.getPermissionSets('', 'All', 1, 15);
        AdminSecurityDataModel.PermissionSetPage customPs = AdminAccessController.getPermissionSets('Test_Admin_Custom_PS', 'Custom', 1, 15);
        Test.stopTest();

        Assert.isNotNull(allPs, 'All perm sets should not be null');
        Assert.isTrue(allPs.totalCount > 0, 'Perm sets should be counted');
        Assert.isTrue(allPs.records.size() > 0, 'Perm sets should be returned');
        Assert.isTrue(allPs.records.size() <= 15, 'Page should not exceed the page size');
        Assert.isTrue(customPs.records.size() > 0, 'Custom perm set should be found by search');
    }

    @isTest
    static void testGetPermissionSetDetail() {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Test_Admin_Custom_PS' LIMIT 1];

        Test.startTest();
        AdminSecurityDataModel.PermissionSetDetail detail = AdminAccessController.getPermissionSetDetail(ps.Id);
        Test.stopTest();

        Assert.isNotNull(detail, 'Permission set detail should not be null');
        Assert.areEqual(ps.Id, detail.permissionSet.id, 'Permission set ID should match');
        Assert.isTrue(detail.objectPermissions.size() > 0, 'Should include Account object permission');
    }

    @isTest
    static void testAssignAndRemovePermissionSet() {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Test_Admin_Custom_PS' LIMIT 1];
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        AdminSecurityDataModel.DmlResult assignRes = AdminAccessController.assignPermissionSetToUser(currentUserId, ps.Id);
        AdminSecurityDataModel.DmlResult removeRes = AdminAccessController.removePermissionSetFromUser(currentUserId, ps.Id);
        Test.stopTest();

        Assert.isTrue(assignRes.success, 'Assignment should succeed');
        Assert.isTrue(removeRes.success, 'Removal should succeed');
    }

    @isTest
    static void testBulkAssignAndRemoveUsers() {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Test_Admin_Custom_PS' LIMIT 1];
        List<Id> userIds = new List<Id>{UserInfo.getUserId()};

        Test.startTest();
        AdminSecurityDataModel.DmlResult bulkAssign = AdminAccessController.assignUsersToPermissionSet(ps.Id, userIds);
        AdminSecurityDataModel.DmlResult bulkRemove = AdminAccessController.removeUsersFromPermissionSet(ps.Id, userIds);
        Test.stopTest();

        Assert.isTrue(bulkAssign.success, 'Bulk assign should succeed');
        Assert.isTrue(bulkRemove.success, 'Bulk remove should succeed');
    }

    @isTest
    static void testGetPermissionSetGroups() {
        Test.startTest();
        List<AdminSecurityDataModel.PermissionSetGroupSummary> groups = AdminAccessController.getPermissionSetGroups('', 'All');
        Test.stopTest();

        Assert.isNotNull(groups, 'Groups list should not be null');
    }

    @isTest
    static void testGetProfilesAndProfileDetail() {
        Profile p = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1];

        Test.startTest();
        List<AdminSecurityDataModel.ProfileSummary> profs = AdminAccessController.getProfiles('', 'All');
        AdminSecurityDataModel.ProfileDetail detail = AdminAccessController.getProfileDetail(p.Id);
        Test.stopTest();

        Assert.isNotNull(profs, 'Profiles should not be null');
        Assert.isTrue(profs.size() > 0, 'Profiles should be returned');
        Assert.isNotNull(detail, 'Profile detail should not be null');
        Assert.isNotNull(detail.systemPermissions, 'System permissions should be included');
        Assert.isTrue(detail.systemPermissions.size() > 0, 'System permissions list should have items');
    }

    @isTest
    static void testGetObjectAndFieldPermissionsForTarget() {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Test_Admin_Custom_PS' LIMIT 1];
        User testUser = [SELECT Id, ProfileId FROM User WHERE Id = :UserInfo.getUserId()];

        Test.startTest();
        AdminSecurityDataModel.ObjectPermPage objPerms = AdminAccessController.getObjectPermissionsForTarget(ps.Id, 'PermissionSet', '', 1, 15);
        AdminSecurityDataModel.FieldPermPage fieldPerms = AdminAccessController.getFieldPermissionsForTarget(ps.Id, 'PermissionSet', 'Account', '', 1, 15);
        List<Map<String, String>> userOpts = AdminAccessController.getUserOptions();
        AdminSecurityDataModel.ObjectPermPage userObjPerms = AdminAccessController.getObjectPermissionsForTarget(testUser.Id, 'User', '', 1, 15);
        AdminSecurityDataModel.FieldPermPage userFieldPerms = AdminAccessController.getFieldPermissionsForTarget(testUser.Id, 'User', 'Account', '', 1, 15);
        Test.stopTest();

        Assert.isNotNull(objPerms, 'Object permissions should not be null');
        Assert.isTrue(objPerms.totalCount > 0, 'Account object permission should be counted');
        Assert.isTrue(objPerms.records.size() > 0, 'Account object permission should be returned');
        Assert.isNotNull(fieldPerms, 'Field permissions should not be null');
        Assert.isTrue(fieldPerms.totalCount > 0, 'Account fields should be counted');
        Assert.isTrue(fieldPerms.records.size() <= 15, 'Field page should not exceed the page size');
        Assert.isNotNull(userOpts, 'User options should not be null');
        Assert.isNotNull(userObjPerms, 'User object permissions should not be null');
        Assert.isNotNull(userFieldPerms, 'User field permissions should not be null');
    }

    @isTest
    static void testGetAppAccessListAndAccessibleObjects() {
        Test.startTest();
        List<AdminSecurityDataModel.AppAccessSummary> apps = AdminAccessController.getAppAccessList('');
        List<AdminSecurityDataModel.SelectOption> objects = AdminAccessController.getAccessibleObjects();
        Test.stopTest();

        Assert.isNotNull(apps, 'App list should not be null');
        Assert.isNotNull(objects, 'Objects list should not be null');
        Assert.isTrue(objects.size() > 0, 'Should find accessible objects');
    }

    @isTest
    static void testSaveObjectAndFieldPermissionsCustom() {
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Test_Admin_Custom_PS' LIMIT 1];

        Test.startTest();
        // Update ObjectPermissions
        AdminSecurityDataModel.DmlResult objRes = AdminAccessController.saveObjectPermissions(
            ps.Id, 'Account', true, true, true, false, false, false
        );
        // Update FieldPermissions
        AdminSecurityDataModel.DmlResult fldRes = AdminAccessController.saveFieldPermissions(
            ps.Id, 'Account', 'Account.AnnualRevenue', true, true
        );
        Test.stopTest();

        Assert.isTrue(objRes.success, 'Object permissions save should succeed');
        Assert.isTrue(fldRes.success, 'Field permissions save should succeed');
    }

    @isTest
    static void testToggleUserActiveStatusSelfProtection() {
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        try {
            AdminAccessController.toggleUserActiveStatus(currentUserId, false);
            Assert.fail('Should have prevented deactivating self');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex.getMessage(), 'Exception message expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testAssignAndRemovePermissionSetGroup() {
        List<PermissionSetGroup> psgList = [SELECT Id FROM PermissionSetGroup LIMIT 1];
        if (!psgList.isEmpty()) {
            Id currentUserId = UserInfo.getUserId();
            Test.startTest();
            AdminSecurityDataModel.DmlResult assignRes = AdminAccessController.assignPermissionSetGroupToUser(currentUserId, psgList[0].Id);
            AdminSecurityDataModel.PermissionSetGroupDetail detail = AdminAccessController.getPermissionSetGroupDetail(psgList[0].Id);
            AdminSecurityDataModel.DmlResult removeRes = AdminAccessController.removePermissionSetGroupFromUser(currentUserId, psgList[0].Id);
            Test.stopTest();

            Assert.isTrue(assignRes.success, 'Group assignment should succeed');
            Assert.isNotNull(detail, 'Group detail should not be null');
            Assert.isTrue(removeRes.success, 'Group removal should succeed');
        }
    }

    @isTest
    static void testBulkAssignAndRemoveUsersToGroup() {
        List<PermissionSetGroup> psgList = [SELECT Id FROM PermissionSetGroup LIMIT 1];
        if (!psgList.isEmpty()) {
            List<Id> userIds = new List<Id>{UserInfo.getUserId()};
            Test.startTest();
            AdminSecurityDataModel.DmlResult bulkAssign = AdminAccessController.assignUsersToPermissionSetGroup(psgList[0].Id, userIds);
            AdminSecurityDataModel.DmlResult bulkRemove = AdminAccessController.removeUsersFromPermissionSetGroup(psgList[0].Id, userIds);
            Test.stopTest();

            Assert.isTrue(bulkAssign.success, 'Bulk group assign should succeed');
            Assert.isTrue(bulkRemove.success, 'Bulk group remove should succeed');
        }
    }

    @isTest
    static void testSavePermissionsMetadataManagedValidation() {
        // Find a profile-owned permission set
        PermissionSet profilePs = [SELECT Id FROM PermissionSet WHERE IsOwnedByProfile = true LIMIT 1];

        Test.startTest();
        try {
            AdminAccessController.saveObjectPermissions(
                profilePs.Id, 'Account', true, true, false, false, false, false
            );
            Assert.fail('Should throw exception for profile-owned permission set');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex.getMessage(), 'Exception message expected for metadata managed permission set');
        }

        try {
            AdminAccessController.saveFieldPermissions(
                profilePs.Id, 'Account', 'Account.AnnualRevenue', true, false
            );
            Assert.fail('Should throw exception for profile-owned field permission');
        } catch (AuraHandledException ex) {
            Assert.isNotNull(ex.getMessage(), 'Exception message expected for metadata managed field permission');
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateGroupAndManageComponents() {
        Id psId = [SELECT Id FROM PermissionSet WHERE Name = 'Test_Admin_Custom_PS' LIMIT 1].Id;

        Test.startTest();
        AdminSecurityDataModel.DmlResult created = AdminAccessController.createPermissionSetGroup('AAC Test Group', '', 'Created by test');
        Assert.isTrue(created.success, 'Group creation should succeed');
        Assert.isNotNull(created.recordId, 'A new group id should be returned');
        Id groupId = created.recordId;

        // The new group offers the custom set as available and has none included yet.
        AdminSecurityDataModel.PermissionSetGroupDetail before = AdminAccessController.getPermissionSetGroupDetail(groupId);
        Assert.areEqual(0, before.includedPermissionSets.size(), 'A new group has no components');
        Boolean offered = false;
        for (AdminSecurityDataModel.PermissionSetSummary ps : before.availablePermissionSets) {
            if (ps.id == psId) {
                offered = true;
            }
        }
        Assert.isTrue(offered, 'The custom permission set should be available to add');

        AdminSecurityDataModel.DmlResult added = AdminAccessController.addPermissionSetsToGroup(groupId, new List<Id>{ psId });
        AdminSecurityDataModel.DmlResult removed = AdminAccessController.removePermissionSetFromGroup(groupId, psId);
        Test.stopTest();

        Assert.isTrue(added.success, 'Adding a permission set to the group should succeed');
        Assert.isTrue(removed.success, 'Removing a permission set from the group should succeed');
        Assert.areEqual(0, [SELECT count() FROM PermissionSetGroupComponent WHERE PermissionSetGroupId = :groupId AND PermissionSetId = :psId],
            'Component should be removed');
    }

    @isTest
    static void testCreateUser() {
        Id profileId = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1].Id;
        String uname = 'aac.newuser.' + DateTime.now().getTime() + '@example.com.invalid';

        Test.startTest();
        AdminSecurityDataModel.DmlResult res = AdminAccessController.createUser('AAC', 'Tester', 'aac.tester@example.com', uname, '', profileId);
        Test.stopTest();

        Assert.isTrue(res.success, 'User creation should succeed');
        Assert.isNotNull(res.recordId, 'A new user id should be returned');
        User created = [SELECT Id, Alias, IsActive FROM User WHERE Id = :res.recordId];
        Assert.isTrue(created.IsActive, 'New user should be active');
        Assert.areEqual('ATester', created.Alias, 'Alias should derive from first initial + last name');
    }

    @isTest
    static void testCreateUserGuards() {
        Integer failures = 0;
        Id profileId = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1].Id;

        Test.startTest();
        try { AdminAccessController.createUser('A', '', 'e@example.com', 'u1@example.com.invalid', '', profileId); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessController.createUser('A', 'B', '', 'u2@example.com.invalid', '', profileId); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessController.createUser('A', 'B', 'e@example.com', 'u3@example.com.invalid', '', null); } catch (AuraHandledException ex) { failures++; }
        Test.stopTest();

        Assert.areEqual(3, failures, 'Invalid user create requests should raise AuraHandledException');
    }

    @isTest
    static void testCreateGroupGuards() {
        Integer failures = 0;
        Test.startTest();
        try { AdminAccessController.createPermissionSetGroup('', '', null); } catch (AuraHandledException ex) { failures++; }
        AdminAccessController.createPermissionSetGroup('AAC Dup Group', 'AAC_Dup_Group', null);
        try { AdminAccessController.createPermissionSetGroup('AAC Dup Group 2', 'AAC_Dup_Group', null); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessController.addPermissionSetsToGroup(null, new List<Id>()); } catch (AuraHandledException ex) { failures++; }
        try { AdminAccessController.removePermissionSetFromGroup(null, null); } catch (AuraHandledException ex) { failures++; }
        Test.stopTest();

        Assert.areEqual(4, failures, 'Invalid group create/component requests should raise AuraHandledException');
    }
}