
## Secure_Wheels_on_SUI
The Secure_wheels module on the Sui blockchain offers a comprehensive system for managing secure car loans. It establishes distinct roles for borrowers and lenders through dedicated structs: Borrower and Lender. These structs encapsulate relevant information like addresses, credit scores, and loan history.

### The module provides a range of functionalities:

- Loan Initiation: Borrowers can initiate loan requests, specifying car details, loan amount, interest rate, and term length. Lenders can approve these requests and add the loans to their active loan portfolio.
- Payment Processing: Borrowers can make payments towards their loans from their escrow accounts. The module facilitates the transfer of these payments to the corresponding lenders.
- Overdue Management: In case of overdue payments, lenders can claim a portion of the borrower's escrow as a penalty.
- Loan Completion: Once a loan is fully paid off, the borrower's obligation is fulfilled, and the loan is marked as closed.
- Data Access: Both borrowers and lenders can access relevant loan details like car information, outstanding balance, payment history, and loan status.

This secure and structured approach to car loan management on Sui empowers both borrowers and lenders with transparency and control throughout the loan lifecycle.