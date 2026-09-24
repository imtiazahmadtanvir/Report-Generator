import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLoggedInUserInfo from '@salesforce/apex/UserRecordPdfController.getLoggedInUserInfo';
import getAllAccessibleObjects from '@salesforce/apex/UserRecordPdfController.getAllAccessibleObjects';
import getDynamicObjectRecords from '@salesforce/apex/UserRecordPdfController.getDynamicObjectRecords';
import { generatePdfBlob, downloadBlobAsFile } from './pdfBuilder';

export default class UserRecordTablePdf extends LightningElement {
    // Current logged-in user information
    @track userInfo = {
        name: 'Loading...',
        email: '',
        profileName: '',
        companyName: '',
        orgName: '',
        smallPhotoUrl: ''
    };

    // Wizard Step: 1 = Object Selection (Explorer), 2 = Field/Column & Data View
    @track currentStep = 1;

    // Objects Catalog (Step 1)
    @track allObjects = [];
    @track selectedObject = 'Account';
    @track selectedObjectLabel = 'Accounts';
    @track selectedObjectIsCustom = false;
    @track objectFilterSearch = '';
    @track objectCategoryFilter = 'all'; // 'all', 'standard', 'custom'

    // Fields & Columns (Step 2)
    @track allAvailableFields = [];
    @track selectedColumns = []; // Array of field API names in exact order: 1st, 2nd, 3rd...
    @track columns = [];
    @track hasOwnerField = true;
    @track isColumnModalOpen = false;
    @track tempSelectedFieldNames = [];

    // Records & Data
    @track allRecords = [];
    @track totalCount = 0;
    @track myRecordCount = 0;
    @track onlyMyRecords = true;
    @track searchTerm = '';

    // Selection
    @track selectedRowIds = [];
    @track selectedRows = [];

    // Sorting
    @track sortedBy = 'Name';
    @track sortedDirection = 'asc';

    // Pagination: Defaults to 15 records per page
    @track currentPage = 1;
    @track pageSize = 15;

    // Modals
    @track isExportModalOpen = false;
    @track isPreviewModalOpen = false;

    // PDF Export Options
    @track pdfTitle = '';
    @track pdfOrientation = 'landscape';
    @track exportScopeOption = 'auto';
    @track pdfRowsPerPage = 15; // User customizable rows per page in PDF (defaults to 15!)

    // Loading indicators
    @track isLoading = false;
    @track isDownloading = false;
    @track isLoadingObjects = false;

    searchTimeout;

    // Icon mapping dictionary
    standardIconMap = {
        account: 'standard:account',
        contact: 'standard:contact',
        opportunity: 'standard:opportunity',
        lead: 'standard:lead',
        case: 'standard:case',
        campaign: 'standard:campaign',
        order: 'standard:orders',
        contract: 'standard:contract',
        product2: 'standard:product',
        pricebook2: 'standard:pricebook',
        asset: 'standard:asset',
        user: 'standard:user',
        solution: 'standard:solution',
        task: 'standard:task',
        event: 'standard:event'
    };

    connectedCallback() {
        this.fetchUserInfo();
        this.fetchObjects();
    }

    async fetchUserInfo() {
        try {
            const info = await getLoggedInUserInfo();
            if (info) {
                this.userInfo = info;
            }
        } catch (error) {
            console.error('Error fetching user info:', error);
        }
    }

    async fetchObjects() {
        this.isLoadingObjects = true;
        try {
            const objs = await getAllAccessibleObjects();
            this.allObjects = (objs || []).map(obj => {
                const lower = obj.value.toLowerCase();
                const icon = this.standardIconMap[lower] || (obj.isCustom ? 'standard:custom' : 'standard:record');
                return {
                    ...obj,
                    icon,
                    iconBg: obj.isCustom ? 'icon-bg-custom' : 'icon-bg-standard'
                };
            });

            // Pre-select Account if available
            if (this.allObjects.length > 0 && !this.selectedObject) {
                const defaultObj = this.allObjects.find(o => o.value.toLowerCase() === 'account') || this.allObjects[0];
                this.selectedObject = defaultObj.value;
                this.selectedObjectLabel = defaultObj.label;
                this.selectedObjectIsCustom = defaultObj.isCustom;
            }
        } catch (error) {
            this.showToast('Error', 'Failed to retrieve accessible objects: ' + (error.body?.message || error.message), 'error');
        } finally {
            this.isLoadingObjects = false;
        }
    }

    // Step 1: Object Filtering & Selection
    handleObjectSearchInput(event) {
        this.objectFilterSearch = event.target.value;
        const filtered = this.filteredDropdownOptions;
        if (filtered.length > 0 && !filtered.some(o => o.value === this.selectedObject)) {
            this.selectedObject = filtered[0].value;
            const matched = this.allObjects.find(o => o.value === this.selectedObject);
            if (matched) {
                this.selectedObjectLabel = matched.label;
                this.selectedObjectIsCustom = matched.isCustom;
            }
        }
    }

    handleDropdownChange(event) {
        const val = event.detail?.value || event.target?.value;
        if (val) {
            this.selectedObject = val;
            const matched = this.allObjects.find(o => o.value === val);
            if (matched) {
                this.selectedObjectLabel = matched.label;
                this.selectedObjectIsCustom = matched.isCustom;
            }
        }
    }

    handleClearObjectSearch() {
        this.objectFilterSearch = '';
    }

    handleSelectCategory(event) {
        this.objectCategoryFilter = event.currentTarget.dataset.category;
    }

    handleCardSelect(event) {
        const objValue = event.currentTarget.dataset.object;
        if (objValue) {
            this.selectedObject = objValue;
            const matched = this.allObjects.find(o => o.value === objValue);
            if (matched) {
                this.selectedObjectLabel = matched.label;
                this.selectedObjectIsCustom = matched.isCustom;
            }
        }
    }

    handleCardDoubleClick(event) {
        this.handleCardSelect(event);
        this.handleProceedToStep2();
    }

    handleProceedToStep2() {
        if (!this.selectedObject) {
            this.showToast('Warning', 'Please select an object to proceed.', 'warning');
            return;
        }
        this.currentStep = 2;
        this.selectedColumns = [];
        this.selectedRowIds = [];
        this.selectedRows = [];
        this.searchTerm = '';
        this.loadObjectData();
    }

    handleBackToStep1() {
        this.currentStep = 1;
    }

    // Step 2: Load Object Fields & Records
    async loadObjectData() {
        this.isLoading = true;
        try {
            const data = await getDynamicObjectRecords({
                objectApiName: this.selectedObject,
                selectedFieldNames: this.selectedColumns,
                onlyMyRecords: this.onlyMyRecords,
                searchTerm: this.searchTerm
            });

            this.selectedObjectLabel = data.objectLabel || this.selectedObject;
            this.selectedObjectIsCustom = data.isCustom;
            this.hasOwnerField = data.hasOwnerField;
            this.allAvailableFields = data.allAvailableFields || [];
            this.columns = data.columns || [];
            this.allRecords = data.records || [];
            this.totalCount = data.totalCount || 0;
            this.myRecordCount = data.myRecordCount || 0;

            // If selectedColumns is empty, initialize with default fields
            if (!this.selectedColumns || this.selectedColumns.length === 0) {
                this.selectedColumns = data.defaultSelectedFields || [];
            }

            this.updateDefaultPdfTitle();

            // Clear invalid selection IDs
            const existingIds = new Set(this.allRecords.map(r => r.Id));
            this.selectedRowIds = this.selectedRowIds.filter(id => existingIds.has(id));
            this.updateSelectedRows();

            this.currentPage = 1;
        } catch (error) {
            this.showToast('Error', 'Failed to load records: ' + (error.body?.message || error.message), 'error');
            this.allRecords = [];
        } finally {
            this.isLoading = false;
        }
    }

    updateDefaultPdfTitle() {
        const scope = (this.hasOwnerField && this.onlyMyRecords) ? 'My Records' : 'All Records';
        this.pdfTitle = `${this.selectedObjectLabel} Report (${scope})`;
    }

    // Column / Field Management Handlers
    handleOpenColumnModal() {
        this.tempSelectedFieldNames = [...this.selectedColumns];
        this.isColumnModalOpen = true;
    }

    handleCloseColumnModal() {
        this.isColumnModalOpen = false;
    }

    handleDualListboxChange(event) {
        this.tempSelectedFieldNames = event.detail.value;
    }

    handleResetDefaultFields() {
        const defaultNames = this.allAvailableFields.slice(0, 6).map(f => f.value);
        this.tempSelectedFieldNames = defaultNames;
    }

    handleSelectAllFields() {
        this.tempSelectedFieldNames = this.allAvailableFields.map(f => f.value);
    }

    handleApplyColumns() {
        if (!this.tempSelectedFieldNames || this.tempSelectedFieldNames.length === 0) {
            this.showToast('Warning', 'Please select at least one column to display.', 'warning');
            return;
        }

        this.selectedColumns = [...this.tempSelectedFieldNames];
        this.isColumnModalOpen = false;
        this.loadObjectData();
        this.showToast('Success', `Updated table with ${this.selectedColumns.length} columns in chosen order.`, 'success');
    }

    // Quick Column Reorder: Move column Left / Up in sequence
    handleMoveColumnUp(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        if (index > 0) {
            const cols = [...this.selectedColumns];
            const temp = cols[index - 1];
            cols[index - 1] = cols[index];
            cols[index] = temp;
            this.selectedColumns = cols;
            this.loadObjectData();
        }
    }

    // Quick Column Reorder: Move column Right / Down in sequence
    handleMoveColumnDown(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        if (index < this.selectedColumns.length - 1) {
            const cols = [...this.selectedColumns];
            const temp = cols[index + 1];
            cols[index + 1] = cols[index];
            cols[index] = temp;
            this.selectedColumns = cols;
            this.loadObjectData();
        }
    }

    // Quick Column Remove
    handleRemoveColumn(event) {
        const colToRemove = event.currentTarget.dataset.field;
        if (this.selectedColumns.length <= 1) {
            this.showToast('Warning', 'At least one column must remain active.', 'warning');
            return;
        }
        this.selectedColumns = this.selectedColumns.filter(c => c !== colToRemove);
        this.loadObjectData();
    }

    // Scope & Search
    handleScopeMyRecords() {
        if (!this.onlyMyRecords) {
            this.onlyMyRecords = true;
            this.loadObjectData();
        }
    }

    handleScopeAllRecords() {
        if (this.onlyMyRecords) {
            this.onlyMyRecords = false;
            this.loadObjectData();
        }
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        clearTimeout(this.searchTimeout);
        this.searchTimeout = setTimeout(() => {
            this.loadObjectData();
        }, 350);
    }

    handleClearSearch() {
        this.searchTerm = '';
        this.loadObjectData();
    }

    handleRefresh() {
        this.loadObjectData();
    }

    // Row Selection
    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedRows = selectedRows;
        this.selectedRowIds = selectedRows.map(row => row.Id);
    }

    updateSelectedRows() {
        const idSet = new Set(this.selectedRowIds);
        this.selectedRows = this.allRecords.filter(r => idSet.has(r.Id));
    }

    handleSelectAllCurrentPage() {
        const pageIds = this.paginatedRecords.map(r => r.Id);
        const combined = Array.from(new Set([...this.selectedRowIds, ...pageIds]));
        this.selectedRowIds = combined;
        this.updateSelectedRows();
    }

    handleClearSelection() {
        this.selectedRowIds = [];
        this.selectedRows = [];
    }

    // Pagination Handlers - default 15
    handlePageSizeChange(event) {
        this.pageSize = parseInt(event.target.value, 10);
        this.pdfRowsPerPage = this.pageSize;
        this.currentPage = 1;
    }

    handlePrevPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
        }
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
        }
    }

    // Sorting Handler
    handleSort(event) {
        const { fieldName: sortedBy, sortDirection: sortedDirection } = event.detail;
        this.sortedBy = sortedBy;
        this.sortedDirection = sortedDirection;
        this.sortData(sortedBy, sortedDirection);
    }

    sortData(fieldname, direction) {
        if (!this.allRecords || this.allRecords.length === 0) return;
        const parseData = [...this.allRecords];
        const isReverse = direction === 'desc' ? 1 : -1;

        parseData.sort((x, y) => {
            let a = x[fieldname] !== undefined ? x[fieldname] : '';
            let b = y[fieldname] !== undefined ? y[fieldname] : '';

            if (typeof a === 'string') a = a.toLowerCase();
            if (typeof b === 'string') b = b.toLowerCase();

            return a > b ? -isReverse : (a < b ? isReverse : 0);
        });

        this.allRecords = parseData;
    }

    // PDF Download & Preview Handlers
    handleOpenExportModal() {
        this.updateDefaultPdfTitle();
        this.pdfRowsPerPage = this.pageSize;
        this.isExportModalOpen = true;
    }

    handleCloseExportModal() {
        this.isExportModalOpen = false;
    }

    handlePdfTitleChange(event) {
        this.pdfTitle = event.target.value;
    }

    handleOrientationChange(event) {
        this.pdfOrientation = event.detail.value;
    }

    handleExportScopeChange(event) {
        this.exportScopeOption = event.detail.value;
    }

    handlePdfRowsPerPageChange(event) {
        this.pdfRowsPerPage = parseInt(event.detail.value, 10);
    }

    handleOpenPreviewModal() {
        this.updateDefaultPdfTitle();
        this.pdfRowsPerPage = this.pageSize;
        this.isPreviewModalOpen = true;
    }

    handleClosePreviewModal() {
        this.isPreviewModalOpen = false;
    }

    handleSystemPrint() {
        window.print();
    }

    handleDownloadFromPreview() {
        this.handleClosePreviewModal();
        this.handleDirectDownloadPdf();
    }

    handleDirectDownloadPdf() {
        this.updateDefaultPdfTitle();
        this.handleConfirmDownloadPdf();
    }

    async handleConfirmDownloadPdf() {
        this.isDownloading = true;
        try {
            const recordsToExport = this.recordsToExport;

            if (recordsToExport.length === 0) {
                this.showToast('Warning', 'No records to download.', 'warning');
                return;
            }

            const cleanScopeLabel = this.exportScopeOption === 'selected' || (this.exportScopeOption === 'auto' && this.hasSelectedRows)
                ? `Selected (${recordsToExport.length} Records)`
                : (this.hasOwnerField && this.onlyMyRecords ? 'My Records' : 'All Records');

            const rpp = parseInt(this.pdfRowsPerPage, 10) || 15;

            const pdfBlob = generatePdfBlob({
                title: this.pdfTitle,
                objectLabel: this.selectedObjectLabel,
                orientation: this.pdfOrientation,
                columns: this.columns,
                records: recordsToExport,
                userInfo: this.userInfo,
                scopeLabel: cleanScopeLabel,
                rowsPerPage: rpp // Strictly 15 per page!
            });

            const timestamp = new Date().toISOString().slice(0, 10);
            const sanitizedTitle = (this.pdfTitle || 'Salesforce_Report').replace(/[^a-zA-Z0-9_-]/g, '_');
            const filename = `${sanitizedTitle}_${timestamp}.pdf`;

            downloadBlobAsFile(pdfBlob, filename);

            const totalPgs = Math.max(1, Math.ceil(recordsToExport.length / rpp));
            this.showToast('Success', `Downloaded ${filename} successfully (${totalPgs} pages)!`, 'success');
            this.handleCloseExportModal();
        } catch (error) {
            console.error('PDF Generation Error:', error);
            this.showToast('Error', 'Failed to generate PDF: ' + (error.message || error), 'error');
        } finally {
            this.isDownloading = false;
        }
    }

    // Getters
    get isStep1() {
        return this.currentStep === 1;
    }

    get isStep2() {
        return this.currentStep === 2;
    }

    get step1BubbleClass() {
        return this.isStep1 ? 'step-bubble step-active' : 'step-bubble step-completed';
    }

    get step2BubbleClass() {
        return this.isStep2 ? 'step-bubble step-active' : 'step-bubble';
    }

    get userInitials() {
        if (!this.userInfo?.name) return 'U';
        const parts = this.userInfo.name.trim().split(/\s+/);
        if (parts.length >= 2) {
            return (parts[0][0] + parts[1][0]).toUpperCase();
        }
        return parts[0].substring(0, 2).toUpperCase();
    }

    // Category Counts
    get countAll() {
        return this.allObjects.length;
    }

    get countStandard() {
        return this.allObjects.filter(o => !o.isCustom).length;
    }

    get countCustom() {
        return this.allObjects.filter(o => o.isCustom).length;
    }

    // Dynamic Filtered Dropdown Options for Choose Salesforce Object Combobox
    get filteredDropdownOptions() {
        const query = (this.objectFilterSearch || '').toLowerCase().trim();
        const category = this.objectCategoryFilter;

        return this.allObjects
            .filter(obj => {
                if (category === 'standard' && obj.isCustom) return false;
                if (category === 'custom' && !obj.isCustom) return false;
                if (query) {
                    const matchesLabel = (obj.label || '').toLowerCase().includes(query);
                    const matchesValue = (obj.value || '').toLowerCase().includes(query);
                    return matchesLabel || matchesValue;
                }
                return true;
            })
            .map(obj => ({
                label: `${obj.label} (${obj.value}) [${obj.isCustom ? 'Custom' : 'Standard'}]`,
                value: obj.value
            }));
    }

    get dropdownOptionCountLabel() {
        const count = this.filteredDropdownOptions.length;
        return `Found ${count} accessible ${count === 1 ? 'object' : 'objects'} (Standard & Custom)`;
    }

    // Dynamic Filtered Object Cards (eliminates giant empty space!)
    get filteredObjectCards() {
        const query = (this.objectFilterSearch || '').toLowerCase().trim();
        const category = this.objectCategoryFilter;

        return this.allObjects.filter(obj => {
            // Category filter
            if (category === 'standard' && obj.isCustom) return false;
            if (category === 'custom' && !obj.isCustom) return false;

            // Search query filter
            if (query) {
                const matchesLabel = (obj.label || '').toLowerCase().includes(query);
                const matchesValue = (obj.value || '').toLowerCase().includes(query);
                return matchesLabel || matchesValue;
            }
            return true;
        }).map(obj => {
            const isSelected = obj.value === this.selectedObject;
            return {
                ...obj,
                cardClass: `object-catalog-card ${isSelected ? 'card-selected' : ''}`,
                badgeClass: `object-pill-badge ${obj.isCustom ? 'badge-custom' : 'badge-standard'}`,
                isSelected
            };
        });
    }

    // Button states for category tabs
    get allTabClass() {
        return `category-filter-btn ${this.objectCategoryFilter === 'all' ? 'active-filter' : ''}`;
    }

    get standardTabClass() {
        return `category-filter-btn ${this.objectCategoryFilter === 'standard' ? 'active-filter' : ''}`;
    }

    get customTabClass() {
        return `category-filter-btn ${this.objectCategoryFilter === 'custom' ? 'active-filter' : ''}`;
    }

    get selectedObjectBadgeClass() {
        return `object-type-badge ${this.selectedObjectIsCustom ? 'badge-custom' : 'badge-standard'}`;
    }

    get selectedObjectBadgeText() {
        return this.selectedObjectIsCustom ? 'Custom Object' : 'Standard Object';
    }

    get myRecordsBtnClass() {
        return `scope-toggle-btn ${this.onlyMyRecords ? 'scope-btn-active' : ''}`;
    }

    get allRecordsBtnClass() {
        return `scope-toggle-btn ${!this.onlyMyRecords ? 'scope-btn-active' : ''}`;
    }

    get searchPlaceholder() {
        return `Search in ${this.selectedObjectLabel}...`;
    }

    get selectedRowsCount() {
        return this.selectedRowIds.length;
    }

    get hasSelectedRows() {
        return this.selectedRowsCount > 0;
    }

    get selectedBadgeClass() {
        return `metric-pill ${this.hasSelectedRows ? 'metric-pill-highlight' : 'metric-pill-subtle'}`;
    }

    get hasRecords() {
        return !this.isLoading && this.allRecords.length > 0;
    }

    get isTableEmpty() {
        return !this.isLoading && this.allRecords.length === 0;
    }

    get filteredRecordCount() {
        return this.allRecords.length;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.allRecords.length / this.pageSize));
    }

    get isFirstPage() {
        return this.currentPage <= 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    get recordRangeStart() {
        if (this.allRecords.length === 0) return 0;
        return (this.currentPage - 1) * this.pageSize + 1;
    }

    get recordRangeEnd() {
        return Math.min(this.currentPage * this.pageSize, this.allRecords.length);
    }

    get paginatedRecords() {
        const start = (this.currentPage - 1) * this.pageSize;
        return this.allRecords.slice(start, start + this.pageSize);
    }

    get currentScopeLabel() {
        return (this.hasOwnerField && this.onlyMyRecords) ? 'My Records' : 'All Accessible Records';
    }

    get currentDateFormatted() {
        return new Date().toLocaleString();
    }

    get recordsToExport() {
        if (this.exportScopeOption === 'selected' || (this.exportScopeOption === 'auto' && this.hasSelectedRows)) {
            return this.selectedRows.length > 0 ? this.selectedRows : this.allRecords;
        }
        return this.allRecords;
    }

    get exportScopeOptions() {
        const hasSelection = this.hasSelectedRows;
        return [
            {
                label: hasSelection ? `Selected Records Only (${this.selectedRowsCount})` : 'All Filtered Records (0 selected)',
                value: 'auto'
            },
            {
                label: `All Filtered Records (${this.filteredRecordCount})`,
                value: 'all'
            },
            {
                label: `Selected Records (${this.selectedRowsCount})`,
                value: 'selected',
                disabled: !hasSelection
            }
        ];
    }

    get orientationOptions() {
        return [
            { label: 'Landscape (Recommended for tables)', value: 'landscape' },
            { label: 'Portrait (Standard vertical)', value: 'portrait' }
        ];
    }

    get pdfRowsPerPageOptions() {
        return [
            { label: '10 Records per Page', value: '10' },
            { label: '15 Records per Page (Standard)', value: '15' },
            { label: '20 Records per Page', value: '20' },
            { label: '25 Records per Page', value: '25' },
            { label: '50 Records per Page', value: '50' }
        ];
    }

    get pdfTotalPagesCount() {
        const rpp = parseInt(this.pdfRowsPerPage, 10) || 15;
        return Math.max(1, Math.ceil(this.recordsToExport.length / rpp));
    }

    get pdfTotalPagesLabel() {
        const pages = this.pdfTotalPagesCount;
        return `${pages} ${pages === 1 ? 'Page' : 'Pages'}`;
    }

    get exportButtonLabel() {
        const count = this.recordsToExport.length;
        const pages = this.pdfTotalPagesCount;
        return `Download PDF (${count} Records • ${pages} ${pages === 1 ? 'Page' : 'Pages'})`;
    }

    get dualListboxOptions() {
        return this.allAvailableFields.map(f => ({
            label: `${f.label} (${f.value})`,
            value: f.value
        }));
    }

    get columnCountLabel() {
        return `${this.columns.length} of ${this.allAvailableFields.length} Fields Active`;
    }

    // Ordered sequence cards (1st Column, 2nd Column, 3rd Column...)
    get orderedColumnChips() {
        const fieldMap = new Map(this.allAvailableFields.map(f => [f.value, f]));
        return this.selectedColumns.map((colName, index) => {
            const def = fieldMap.get(colName);
            const ordinal = this.getOrdinalSuffix(index + 1);
            return {
                fieldName: colName,
                label: def ? def.label : colName,
                orderNumber: index + 1,
                orderBadge: `${index + 1}${ordinal} Column`,
                isFirst: index === 0,
                isLast: index === this.selectedColumns.length - 1,
                index
            };
        });
    }

    getOrdinalSuffix(num) {
        const j = num % 10;
        const k = num % 100;
        if (j === 1 && k !== 11) return 'st';
        if (j === 2 && k !== 12) return 'nd';
        if (j === 3 && k !== 13) return 'rd';
        return 'th';
    }

    // Multi-page preview structure matching exact PDF output
    get previewPages() {
        const records = this.recordsToExport;
        const rpp = parseInt(this.pdfRowsPerPage, 10) || 15;
        const pages = [];
        let currentIdx = 0;
        let pageNum = 1;
        const totalPages = Math.max(1, Math.ceil(records.length / rpp));

        if (records.length === 0) {
            pages.push({
                pageNumber: 1,
                totalPages: 1,
                records: [],
                isFirstPage: true
            });
        } else {
            while (currentIdx < records.length) {
                const slice = records.slice(currentIdx, currentIdx + rpp);
                const mapped = slice.map(rec => {
                    const cells = this.columns.map(col => {
                        let val = rec[col.fieldName];
                        if (val === null || val === undefined || val === '') {
                            val = '-';
                        } else if (col.type === 'currency' && typeof val === 'number') {
                            val = '$' + val.toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
                        }
                        return { field: col.fieldName, value: val };
                    });
                    return { Id: rec.Id, cells };
                });

                pages.push({
                    pageNumber: pageNum,
                    totalPages,
                    records: mapped,
                    isFirstPage: pageNum === 1
                });

                pageNum++;
                currentIdx += rpp;
            }
        }
        return pages;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
