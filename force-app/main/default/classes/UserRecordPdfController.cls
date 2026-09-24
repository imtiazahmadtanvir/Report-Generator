/**
 * @description Dynamic Controller for fetching accessible Standard and Custom Objects,
 * their fields, and records for dynamic table display and PDF reporting.
 */
public with sharing class UserRecordPdfController {

    public class UserInfoWrapper {
        @AuraEnabled public String userId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String profileName { get; set; }
        @AuraEnabled public String companyName { get; set; }
        @AuraEnabled public String orgName { get; set; }
        @AuraEnabled public String smallPhotoUrl { get; set; }
    }

    public class ObjectOption implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; } // API Name
        @AuraEnabled public Boolean isCustom { get; set; }
        @AuraEnabled public String typeBadge { get; set; }

        public ObjectOption(String label, String value, Boolean isCustom) {
            this.label = label;
            this.value = value;
            this.isCustom = isCustom;
            this.typeBadge = isCustom ? 'Custom' : 'Standard';
        }

        public Integer compareTo(Object compareTo) {
            ObjectOption other = (ObjectOption)compareTo;
            return this.label.toLowerCase().compareTo(other.label.toLowerCase());
        }
    }

    public class FieldOption implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; } // Field API Name
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public Boolean isSortable { get; set; }
        @AuraEnabled public Boolean isNameField { get; set; }
        @AuraEnabled public Integer initialWidth { get; set; }

        public FieldOption(String label, String value, String type, Boolean isSortable, Boolean isNameField, Integer initialWidth) {
            this.label = label;
            this.value = value;
            this.type = type;
            this.isSortable = isSortable;
            this.isNameField = isNameField;
            this.initialWidth = initialWidth != null ? initialWidth : 150;
        }

        public Integer compareTo(Object compareTo) {
            FieldOption other = (FieldOption)compareTo;
            return this.label.toLowerCase().compareTo(other.label.toLowerCase());
        }
    }

    public class ColumnDefinition {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String fieldName { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public Boolean sortable { get; set; }
        @AuraEnabled public Integer initialWidth { get; set; }

        public ColumnDefinition(String label, String fieldName, String type, Boolean sortable, Integer initialWidth) {
            this.label = label;
            this.fieldName = fieldName;
            this.type = type;
            this.sortable = sortable;
            this.initialWidth = initialWidth;
        }
    }

    public class DynamicTableResponse {
        @AuraEnabled public String objectApiName { get; set; }
        @AuraEnabled public String objectLabel { get; set; }
        @AuraEnabled public Boolean isCustom { get; set; }
        @AuraEnabled public Boolean hasOwnerField { get; set; }
        @AuraEnabled public List<ColumnDefinition> columns { get; set; }
        @AuraEnabled public List<FieldOption> allAvailableFields { get; set; }
        @AuraEnabled public List<String> defaultSelectedFields { get; set; }
        @AuraEnabled public List<Map<String, Object>> records { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Integer myRecordCount { get; set; }
    }

    /**
     * @description Fetch details of currently logged-in user
     */
    @AuraEnabled(cacheable=true)
    public static UserInfoWrapper getLoggedInUserInfo() {
        try {
            User currentUser = [
                SELECT Id, Name, Email, CompanyName, SmallPhotoUrl, Profile.Name
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            Organization org = [
                SELECT Id, Name
                FROM Organization
                LIMIT 1
            ];

            UserInfoWrapper info = new UserInfoWrapper();
            info.userId = currentUser.Id;
            info.name = currentUser.Name;
            info.email = currentUser.Email;
            info.companyName = currentUser.CompanyName != null ? currentUser.CompanyName : org.Name;
            info.orgName = org.Name;
            info.profileName = currentUser.Profile != null ? currentUser.Profile.Name : 'Standard User';
            info.smallPhotoUrl = currentUser.SmallPhotoUrl;
            return info;
        } catch (Exception ex) {
            throw new AuraHandledException('Error fetching user info: ' + ex.getMessage());
        }
    }

    /**
     * @description Return ALL accessible Standard and Custom Objects
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getAllAccessibleObjects() {
        try {
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            List<ObjectOption> options = new List<ObjectOption>();

            for (String key : globalDescribe.keySet()) {
                String lowerKey = key.toLowerCase();
                
                // Exclude purely technical and internal system objects
                if (lowerKey.endsWith('__share') || lowerKey.endsWith('__history') || 
                    lowerKey.endsWith('__feed') || lowerKey.endsWith('__changeevent') ||
                    lowerKey.endsWith('__tag') || lowerKey.endsWith('__e') ||
                    lowerKey.endsWith('__hd') ||
                    lowerKey.startsWith('auth') || lowerKey.startsWith('apex') || 
                    lowerKey.startsWith('async') || lowerKey.startsWith('cron') ||
                    lowerKey.startsWith('processinstance') || lowerKey.startsWith('vote') ||
                    lowerKey.startsWith('datastream') || lowerKey.startsWith('setupaudit') ||
                    lowerKey.startsWith('login') || lowerKey.startsWith('staticresource') ||
                    lowerKey.startsWith('contentdocumentlink') || lowerKey.startsWith('attachedcontentdocument')) {
                    continue;
                }

                Schema.DescribeSObjectResult describe = globalDescribe.get(key).getDescribe();
                if (describe.isAccessible() && describe.isQueryable() && !describe.isCustomSetting() && !describe.isDeprecatedAndHidden()) {
                    options.add(new ObjectOption(describe.getLabel(), describe.getName(), describe.isCustom()));
                }
            }

            options.sort();
            return options;
        } catch (Exception ex) {
            throw new AuraHandledException('Error retrieving objects: ' + ex.getMessage());
        }
    }

    /**
     * @description Fetch all accessible fields for the selected object
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getObjectFields(String objectApiName) {
        try {
            if (String.isBlank(objectApiName)) {
                return new List<FieldOption>();
            }

            Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
            if (!gd.containsKey(objectApiName)) {
                throw new AuraHandledException('Object not found: ' + objectApiName);
            }

            Schema.DescribeSObjectResult describe = gd.get(objectApiName).getDescribe();
            if (!describe.isAccessible()) {
                throw new AuraHandledException('Access denied for object: ' + objectApiName);
            }

            Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();
            List<FieldOption> fieldOptions = new List<FieldOption>();

            for (String fieldKey : fieldMap.keySet()) {
                Schema.DescribeFieldResult fd = fieldMap.get(fieldKey).getDescribe();
                if (fd.isAccessible()) {
                    String fieldType = String.valueOf(fd.getType()).toLowerCase();
                    Integer width = 150;
                    if (fieldType == 'datetime' || fieldType == 'date') width = 130;
                    if (fieldType == 'currency') width = 140;
                    if (fieldType == 'email' || fieldType == 'url') width = 180;
                    if (fd.isNameField()) width = 200;

                    fieldOptions.add(new FieldOption(
                        fd.getLabel(),
                        fd.getName(),
                        fieldType,
                        fd.isSortable(),
                        fd.isNameField(),
                        width
                    ));
                }
            }

            fieldOptions.sort();
            return fieldOptions;
        } catch (Exception ex) {
            throw new AuraHandledException('Error retrieving fields: ' + ex.getMessage());
        }
    }

    /**
     * @description Fetch records dynamically for ANY object and user-selected fields
     */
    @AuraEnabled(cacheable=false)
    public static DynamicTableResponse getDynamicObjectRecords(
        String objectApiName, 
        List<String> selectedFieldNames, 
        Boolean onlyMyRecords, 
        String searchTerm
    ) {
        try {
            if (String.isBlank(objectApiName)) {
                objectApiName = 'Account';
            }

            Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
            if (!gd.containsKey(objectApiName)) {
                throw new AuraHandledException('Invalid object: ' + objectApiName);
            }

            Schema.DescribeSObjectResult describe = gd.get(objectApiName).getDescribe();
            if (!describe.isAccessible() || !describe.isQueryable()) {
                throw new AuraHandledException('Access denied to object: ' + objectApiName);
            }

            Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();
            Boolean hasOwner = fieldMap.containsKey('ownerid');
            String nameField = 'Name';
            for (String fName : fieldMap.keySet()) {
                if (fieldMap.get(fName).getDescribe().isNameField()) {
                    nameField = fieldMap.get(fName).getDescribe().getName();
                    break;
                }
            }

            // Determine all available fields
            List<FieldOption> allFields = new List<FieldOption>();
            for (String fKey : fieldMap.keySet()) {
                Schema.DescribeFieldResult fd = fieldMap.get(fKey).getDescribe();
                if (fd.isAccessible()) {
                    String fieldType = String.valueOf(fd.getType()).toLowerCase();
                    Integer width = fd.isNameField() ? 200 : 150;
                    allFields.add(new FieldOption(fd.getLabel(), fd.getName(), fieldType, fd.isSortable(), fd.isNameField(), width));
                }
            }
            allFields.sort();

            // Validate and sanitize selected fields
            List<String> validFieldNames = new List<String>();
            Set<String> addedFields = new Set<String>();

            if (selectedFieldNames != null && !selectedFieldNames.isEmpty()) {
                for (String reqField : selectedFieldNames) {
                    if (String.isNotBlank(reqField)) {
                        String lower = reqField.toLowerCase();
                        if (fieldMap.containsKey(lower) && !addedFields.contains(lower)) {
                            Schema.DescribeFieldResult fd = fieldMap.get(lower).getDescribe();
                            if (fd.isAccessible()) {
                                validFieldNames.add(fd.getName());
                                addedFields.add(lower);
                            }
                        }
                    }
                }
            }

            // If no valid fields requested, pick default fields
            if (validFieldNames.isEmpty()) {
                if (fieldMap.containsKey(nameField.toLowerCase())) {
                    validFieldNames.add(nameField);
                    addedFields.add(nameField.toLowerCase());
                }
                // Pick up to 5 additional common accessible fields
                for (FieldOption fo : allFields) {
                    if (validFieldNames.size() >= 6) break;
                    if (!addedFields.contains(fo.value.toLowerCase())) {
                        validFieldNames.add(fo.value);
                        addedFields.add(fo.value.toLowerCase());
                    }
                }
            }

            // Construct Column Definitions in the user-selected order
            List<ColumnDefinition> colDefs = new List<ColumnDefinition>();
            for (String f : validFieldNames) {
                Schema.DescribeFieldResult fd = fieldMap.get(f.toLowerCase()).getDescribe();
                String colType = mapSfdcTypeToDatatableType(String.valueOf(fd.getType()).toLowerCase());
                Integer w = fd.isNameField() ? 200 : 150;
                colDefs.add(new ColumnDefinition(fd.getLabel(), fd.getName(), colType, fd.isSortable(), w));
            }

            // Build dynamic SOQL query
            Set<String> queryFields = new Set<String>{'Id'};
            for (String f : validFieldNames) {
                queryFields.add(f);
            }
            if (hasOwner && !queryFields.contains('OwnerId')) {
                queryFields.add('OwnerId');
            }

            String soql = 'SELECT ' + String.join(new List<String>(queryFields), ', ') + ' FROM ' + String.escapeSingleQuotes(objectApiName);
            List<String> conditions = new List<String>();
            Id currentUserId = UserInfo.getUserId();

            if (onlyMyRecords && hasOwner) {
                conditions.add('OwnerId = :currentUserId');
            }

            if (String.isNotBlank(searchTerm)) {
                String sanitized = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
                List<String> searchOrClauses = new List<String>();
                // Search against Name field or text fields
                for (String vf : validFieldNames) {
                    Schema.DescribeFieldResult fd = fieldMap.get(vf.toLowerCase()).getDescribe();
                    String ft = String.valueOf(fd.getType()).toLowerCase();
                    if (ft == 'string' || ft == 'textarea' || ft == 'email' || ft == 'phone' || ft == 'picklist') {
                        searchOrClauses.add(vf + ' LIKE :sanitized');
                    }
                }
                if (!searchOrClauses.isEmpty()) {
                    conditions.add('(' + String.join(searchOrClauses, ' OR ') + ')');
                }
            }

            if (!conditions.isEmpty()) {
                soql += ' WHERE ' + String.join(conditions, ' AND ');
            }

            String orderField = fieldMap.containsKey(nameField.toLowerCase()) ? nameField : 'Id';
            soql += ' WITH USER_MODE ORDER BY ' + orderField + ' ASC LIMIT 500';

            List<SObject> rawRecords = Database.query(soql);
            List<Map<String, Object>> mappedRecords = new List<Map<String, Object>>();

            for (SObject sobj : rawRecords) {
                Map<String, Object> row = new Map<String, Object>();
                row.put('Id', sobj.Id);

                for (String colField : validFieldNames) {
                    Object val = sobj.get(colField);
                    if (val == null) {
                        row.put(colField, '-');
                    } else if (val instanceof Datetime) {
                        row.put(colField, ((Datetime)val).format('yyyy-MM-dd HH:mm'));
                    } else if (val instanceof Date) {
                        row.put(colField, String.valueOf((Date)val));
                    } else {
                        row.put(colField, val);
                    }
                }
                mappedRecords.add(row);
            }

            DynamicTableResponse response = new DynamicTableResponse();
            response.objectApiName = describe.getName();
            response.objectLabel = describe.getLabel();
            response.isCustom = describe.isCustom();
            response.hasOwnerField = hasOwner;
            response.columns = colDefs;
            response.allAvailableFields = allFields;
            response.defaultSelectedFields = validFieldNames;
            response.records = mappedRecords;
            response.totalCount = mappedRecords.size();

            if (hasOwner) {
                String countSoql = 'SELECT COUNT() FROM ' + String.escapeSingleQuotes(objectApiName) + ' WHERE OwnerId = :currentUserId WITH USER_MODE';
                response.myRecordCount = Database.countQuery(countSoql);
            } else {
                response.myRecordCount = mappedRecords.size();
            }

            return response;
        } catch (Exception ex) {
            throw new AuraHandledException('Error fetching dynamic records: ' + ex.getMessage());
        }
    }

    private static String mapSfdcTypeToDatatableType(String sfdcType) {
        if (sfdcType == 'email') return 'email';
        if (sfdcType == 'phone') return 'phone';
        if (sfdcType == 'currency') return 'currency';
        if (sfdcType == 'url') return 'url';
        if (sfdcType == 'date' || sfdcType == 'datetime') return 'text';
        if (sfdcType == 'integer' || sfdcType == 'double' || sfdcType == 'percent') return 'number';
        if (sfdcType == 'boolean') return 'boolean';
        return 'text';
    }
}
