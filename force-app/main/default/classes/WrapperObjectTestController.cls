public with sharing class WrapperObjectTestController {
    
    @AuraEnabled(cacheable=true)
    public static List<Account> getAccountsAndContacts() {
        // Step 1: Run the SOQL query and assign to a List variable
        List<Account> accountList = [
            SELECT Id, Name, Phone,
            (SELECT Id, Name FROM Contacts)
            FROM Account
            
            LIMIT 10
        ];
        system.debug('accountList::'+accountList);
        // Step 2: Return the List
        return accountList;
    }
}