import { LightningElement, api, track, wire } from 'lwc';
import getOpportunityContext from '@salesforce/apex/SmartDealController.getOpportunityContext';
import recalculateDealHealth from '@salesforce/apex/SmartDealController.recalculateDealHealth';
import refreshExternalPricing from '@salesforce/apex/SmartDealController.refreshExternalPricing';
import saveLineItems from '@salesforce/apex/SmartDealController.saveLineItems';
import { updateRecord } from "lightning/uiRecordApi";
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {refreshApex } from '@salesforce/apex';
import getRelatedRecords from '@salesforce/apex/SmartDealController.getRelatedRecords';

export default class SmartDealPack extends LightningElement {

    @api recordId;
    @track opportunity = {};
    @track lineItems = [];
    @track dealHealthScore;
    @track rows = [];
    @track draftValues = [];
    wiredContacts;
    @track relatedRecords = [];
    currentTab = 'Contact';
    rowLimit = 10;
    rowOffset = 0;


    isLoading = false;
    isSaveProducts = false;

    // Columns for the existing items datatable
    columns = [
        { label: 'Product', fieldName: 'productName' },
        { label: 'Quantity', fieldName: 'Quantity', editable: true },
        { label: 'Unit Price', fieldName: 'UnitPrice', type: 'currency' },
        { label: 'Discount %', fieldName: 'Discount', editable: true },
        { label: 'External Price', fieldName: 'externalUnitPrice', type: 'currency' },
        { label: 'In Stock', fieldName: 'isInStock', type: 'boolean' }
    ];
    // Define columns for different tabs
    contactColumns = [
        { label: 'Name', fieldName: 'Name' },
        { label: 'Email', fieldName: 'Email', type: 'email' }
    ];
    caseColumns = [
        { label: 'Subject', fieldName: 'Subject' },
        { label: 'Status', fieldName: 'Status' }
    ];
    installColumns = [
        { label: 'Installation Name', fieldName: 'Name' },
        { label: 'Status', fieldName: 'Status__c' }
    ];

    

    @wire(getOpportunityContext, { oppId: '$recordId' })
    processLineItems(result) {
        this.wiredItems = result; 
        const { data, error } = result;

        if (data) {
            this.opportunity = data.opportunity;
            this.lineItems = data.lineItems;
            this.dealHealthScore = data.dealHealthScore;
            this.error = undefined;
        } else if (error) {
            this.showToast('Error', error.body.message, 'error');
        }
    }

    handleRefreshPricing() {
        this.isLoading = true;
        refreshExternalPricing({ oppId: this.recordId })
            .then(() => {
                this.showToast(
                    'Success',
                    'External pricing refreshed',
                    'success'
                );
                return refreshApex(this.wiredItems);
            })
            .catch(e =>
                this.showToast('Error', e.body.message, 'error')
            )
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Controls general visibility of the dynamic section
    get hasRows() {
        return this.rows.length > 0;
    }

    // Handles data entry for all dynamic fields (Record Picker & standard inputs)
    handleInputChange(event) {
        const index = event.target.dataset.index;
        const name = event.target.name;
        let value;

        if (name === 'productId') {
            value = event.detail.recordId; 
        } else if (name === 'inStock') {
            value = event.target.checked;
        } else {
            value = event.target.value;
        }

        this.rows[index][name] = value;
    }

    // Logic for Add Row Button
    handleAddRow() {
        const newRow = {
            id: Date.now() + Math.random(),
            productId: '',
            quantity: null,
            unitPrice: null,
            discount: null,
            externalPrice: null,
            inStock: false
        };
        this.rows = [...this.rows, newRow];
        this.isSaveProducts = true; // Show Save button
    }

    // Logic for Delete Icon
    handleRemoveRow(event) {
        const index = event.target.dataset.index;
        let tempRows = [...this.rows];
        tempRows.splice(index, 1);
        this.rows = tempRows;
        
        // Hide Save button if no rows left
        this.isSaveProducts = this.rows.length > 0;
    }

    // Logic for Save Button
    handleSave() {
        if (this.rows.length === 0) {
            this.showToast('Warning', 'No rows to save', 'warning');
            return;
        }

        this.isLoading = true;

        // Convert List to JSON String to avoid "Unsupported Parameter Type" error
        const rowDataString = JSON.stringify(this.rows);

        saveLineItems({ 
            oppId: this.recordId, 
            rowData: rowDataString 
        })
        .then(() => {
            this.showToast('Success', 'Products added to Opportunity', 'success');
            this.rows = []; 
            this.isSaveProducts = false; 
            return this.loadData(); // Refresh the top datatable
        })
        .catch(error => {
            console.error('Error info:', error);
            this.showToast('Error saving records', error.body.message, 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // Handles the save event triggered by inline editing
    handleInlineSave(event) {
        // Extract the draft values from the onsave event
        this.draftValues = event.detail.draftValues;
        // Convert draft values into record input objects
        const recordInputs = this.draftValues.slice().map(draft => {
        const fields = { ...draft };
        return { fields };
        });
        // Perform update operations for all draft records updateRecord uiRecordApi
        const updatePromises = recordInputs.map(recordInput => updateRecord(recordInput));
        Promise.all(updatePromises).then(() => {
            //display success toast message
            this.dispatchEvent(
            new ShowToastEvent({
            title: 'Updated',
            message: 'Records Updated Successfully',
            variant: 'success'
            })
        );
        // Clear draft values after successful update
        this.draftValues = [];
        // Refresh the data table after clicking Save
        return refreshApex(this.wiredItems);;
        }).catch(error => {
            // Handle errors during update
            this.dispatchEvent(
                new ShowToastEvent({
                title: 'Error',
                message: 'An Error '+error,
                variant: 'error'
                })
            );
        });
    }

    handleTabActive(event) {
        this.currentTab = event.target.dataset.id;
        this.relatedRecords = [];
        this.rowOffset = 0;
        // Reset the datatable to allow infinite loading again for the new tab
        const datatable = this.template.querySelector(`lightning-datatable[data-id="${this.currentTab}"]`);
        if (datatable) {
            datatable.enableInfiniteLoading = true;
        }
        this.fetchRecords();
    }

    fetchRecords() {
        return getRelatedRecords({
            parentId: this.recordId,
            objectName: this.currentTab,
            rowLimit: this.rowLimit,
            rowOffset: this.rowOffset
        })
        .then(result => {
            this.relatedRecords = [...this.relatedRecords, ...result];
             // If returned records are less than the limit, we've reached the end
            if (result.length < this.rowLimit) {
                const datatable = this.template.querySelector(`lightning-datatable[data-id="${this.currentTab}"]`);
                if (datatable) {
                    datatable.enableInfiniteLoading = false;
                }
            }
        })
        .catch(error => console.error(error));
    }

    loadMoreData(event) {
        const { target } = event;
        target.isLoading = true;
        this.rowOffset += this.rowLimit;
        
        this.fetchRecords().then(() => {
            target.isLoading = false;
        });
    }
}