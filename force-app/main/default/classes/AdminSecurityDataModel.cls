/**
 * @description Data Transfer Objects and Wrappers for Salesforce Admin Access Console
 */
public with sharing class AdminSecurityDataModel {

    public class AdminSecurityOverview {
        @AuraEnabled public Integer totalUsers { get; set; }
        @AuraEnabled public Integer activeUsers { get; set; }
        @AuraEnabled public Integer totalPermSets { get; set; }
        @AuraEnabled public Integer customPermSets { get; set; }
        @AuraEnabled public Integer totalPermSetGroups { get; set; }
        @AuraEnabled public Integer totalProfiles { get; set; }
        @AuraEnabled public Integer totalApps { get; set; }
        @AuraEnabled public String currentAdminName { get; set; }
        @AuraEnabled public String currentAdminProfile { get; set; }
        @AuraEnabled public Boolean isAuthorizedAdmin { get; set; }
    }

    public class AdminUserInfo implements Comparable {
        @AuraEnabled public String userId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String username { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String profileId { get; set; }
        @AuraEnabled public String profileName { get; set; }
        @AuraEnabled public String roleId { get; set; }
        @AuraEnabled public String roleName { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public String statusBadge { get; set; }
        @AuraEnabled public String smallPhotoUrl { get; set; }
        @AuraEnabled public Integer permSetCount { get; set; }
        @AuraEnabled public Integer permSetGroupCount { get; set; }
        @AuraEnabled public String createdDateFormatted { get; set; }
        @AuraEnabled public String lastLoginFormatted { get; set; }

        public Integer compareTo(Object compareTo) {
            AdminUserInfo other = (AdminUserInfo)compareTo;
            if (this.name == null) return -1;
            if (other.name == null) return 1;
            return this.name.toLowerCase().compareTo(other.name.toLowerCase());
        }
    }

    public class UserDetailView {
        @AuraEnabled public AdminUserInfo user { get; set; }
        @AuraEnabled public List<PermissionSetSummary> assignedPermissionSets { get; set; }
        @AuraEnabled public List<PermissionSetSummary> availablePermissionSets { get; set; }
        @AuraEnabled public List<PermissionSetGroupSummary> assignedPermissionSetGroups { get; set; }
        @AuraEnabled public List<PermissionSetGroupSummary> availablePermissionSetGroups { get; set; }
        @AuraEnabled public List<ObjectPermItem> effectiveObjectPermissions { get; set; }
    }

    public class PermissionSetSummary implements Comparable {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String licenseName { get; set; }
        @AuraEnabled public Boolean isCustom { get; set; }
        @AuraEnabled public String typeBadge { get; set; }
        @AuraEnabled public Boolean isOwnedByProfile { get; set; }
        @AuraEnabled public String profileId { get; set; }
        @AuraEnabled public String profileName { get; set; }
        @AuraEnabled public Integer userCount { get; set; }
        @AuraEnabled public String createdDateFormatted { get; set; }
        @AuraEnabled public Boolean isEditable { get; set; }

        public Integer compareTo(Object compareTo) {
            PermissionSetSummary other = (PermissionSetSummary)compareTo;
            if (this.label == null) return -1;
            if (other.label == null) return 1;
            return this.label.toLowerCase().compareTo(other.label.toLowerCase());
        }
    }

    public class PermissionSetDetail {
        @AuraEnabled public PermissionSetSummary permissionSet { get; set; }
        @AuraEnabled public List<AdminUserInfo> assignedUsers { get; set; }
        @AuraEnabled public List<AdminUserInfo> availableUsers { get; set; }
        @AuraEnabled public List<ObjectPermItem> objectPermissions { get; set; }
        @AuraEnabled public List<FieldPermItem> fieldPermissions { get; set; }
    }

    public class PermissionSetGroupSummary implements Comparable {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String masterLabel { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Integer componentCount { get; set; }
        @AuraEnabled public Integer assignedUserCount { get; set; }
        @AuraEnabled public List<String> includedPermSetNames { get; set; }

        public Integer compareTo(Object compareTo) {
            PermissionSetGroupSummary other = (PermissionSetGroupSummary)compareTo;
            if (this.masterLabel == null) return -1;
            if (other.masterLabel == null) return 1;
            return this.masterLabel.toLowerCase().compareTo(other.masterLabel.toLowerCase());
        }
    }

    public class PermissionSetGroupDetail {
        @AuraEnabled public PermissionSetGroupSummary groupSummary { get; set; }
        @AuraEnabled public List<PermissionSetSummary> includedPermissionSets { get; set; }
        @AuraEnabled public List<AdminUserInfo> assignedUsers { get; set; }
        @AuraEnabled public List<AdminUserInfo> availableUsers { get; set; }
    }

    public class ProfileSummary implements Comparable {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String userType { get; set; }
        @AuraEnabled public String userLicenseName { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Integer userCount { get; set; }
        @AuraEnabled public String permissionSetId { get; set; }
        @AuraEnabled public String createdDateFormatted { get; set; }

        public Integer compareTo(Object compareTo) {
            ProfileSummary other = (ProfileSummary)compareTo;
            if (this.name == null) return -1;
            if (other.name == null) return 1;
            return this.name.toLowerCase().compareTo(other.name.toLowerCase());
        }
    }

    public class ProfileDetail {
        @AuraEnabled public ProfileSummary profile { get; set; }
        @AuraEnabled public List<AdminUserInfo> associatedUsers { get; set; }
        @AuraEnabled public List<ObjectPermItem> objectPermissions { get; set; }
        @AuraEnabled public List<KeySystemPermission> systemPermissions { get; set; }
    }

    public class KeySystemPermission {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Boolean isEnabled { get; set; }
        @AuraEnabled public String category { get; set; }

        public KeySystemPermission(String name, String label, String description, Boolean isEnabled, String category) {
            this.name = name;
            this.label = label;
            this.description = description;
            this.isEnabled = isEnabled;
            this.category = category;
        }
    }

    public class ObjectPermItem implements Comparable {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String parentId { get; set; }
        @AuraEnabled public String parentName { get; set; }
        @AuraEnabled public String parentType { get; set; } // 'Profile' or 'PermissionSet'
        @AuraEnabled public String sobjectType { get; set; }
        @AuraEnabled public String sobjectLabel { get; set; }
        @AuraEnabled public Boolean isCustomObject { get; set; }
        @AuraEnabled public Boolean permissionsRead { get; set; }
        @AuraEnabled public Boolean permissionsCreate { get; set; }
        @AuraEnabled public Boolean permissionsEdit { get; set; }
        @AuraEnabled public Boolean permissionsDelete { get; set; }
        @AuraEnabled public Boolean permissionsViewAllRecords { get; set; }
        @AuraEnabled public Boolean permissionsModifyAllRecords { get; set; }
        @AuraEnabled public Boolean isEditable { get; set; } // true only if custom permission set
        @AuraEnabled public String source { get; set; } // where user got this permission

        public Integer compareTo(Object compareTo) {
            ObjectPermItem other = (ObjectPermItem)compareTo;
            String thisKey = (this.sobjectLabel != null ? this.sobjectLabel : this.sobjectType);
            String otherKey = (other.sobjectLabel != null ? other.sobjectLabel : other.sobjectType);
            return thisKey.toLowerCase().compareTo(otherKey.toLowerCase());
        }
    }

    public class FieldPermItem implements Comparable {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String parentId { get; set; }
        @AuraEnabled public String parentName { get; set; }
        @AuraEnabled public String sobjectType { get; set; }
        @AuraEnabled public String field { get; set; }
        @AuraEnabled public String fieldLabel { get; set; }
        @AuraEnabled public String dataType { get; set; }
        @AuraEnabled public Boolean permissionsRead { get; set; }
        @AuraEnabled public Boolean permissionsEdit { get; set; }
        @AuraEnabled public Boolean isCustom { get; set; }
        @AuraEnabled public Boolean isEditable { get; set; }

        public Integer compareTo(Object compareTo) {
            FieldPermItem other = (FieldPermItem)compareTo;
            String thisKey = (this.fieldLabel != null ? this.fieldLabel : this.field);
            String otherKey = (other.fieldLabel != null ? other.fieldLabel : other.field);
            return thisKey.toLowerCase().compareTo(otherKey.toLowerCase());
        }
    }

    public class AppAccessSummary implements Comparable {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public Boolean isVisible { get; set; }
        @AuraEnabled public Boolean isAccessible { get; set; }
        @AuraEnabled public List<String> profilesWithAccess { get; set; }
        @AuraEnabled public List<String> permSetsWithAccess { get; set; }
        @AuraEnabled public Integer profilesCount { get; set; }
        @AuraEnabled public Integer permSetsCount { get; set; }
        @AuraEnabled public String setupUrl { get; set; }

        public Integer compareTo(Object compareTo) {
            AppAccessSummary other = (AppAccessSummary)compareTo;
            if (this.label == null) return -1;
            if (other.label == null) return 1;
            return this.label.toLowerCase().compareTo(other.label.toLowerCase());
        }
    }

    public class SelectOption implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String subLabel { get; set; }

        public SelectOption(String label, String value) {
            this.label = label;
            this.value = value;
            this.subLabel = '';
        }

        public SelectOption(String label, String value, String subLabel) {
            this.label = label;
            this.value = value;
            this.subLabel = subLabel;
        }

        public Integer compareTo(Object compareTo) {
            SelectOption other = (SelectOption)compareTo;
            if (this.label == null) return -1;
            if (other.label == null) return 1;
            return this.label.toLowerCase().compareTo(other.label.toLowerCase());
        }
    }

    public class DmlResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String recordId { get; set; }

        public DmlResult(Boolean success, String message) {
            this.success = success;
            this.message = message;
            this.recordId = null;
        }

        public DmlResult(Boolean success, String message, String recordId) {
            this.success = success;
            this.message = message;
            this.recordId = recordId;
        }
    }
}
