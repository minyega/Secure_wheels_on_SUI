module Secure_wheels::wheel {
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID};
    use sui::balance::{Self, Balance};
    use std::option::{Option, none, some};
    use sui::tx_context::{Self, TxContext};

    // Constants
    const Error_InvalidLoan: u64 = 1;
    const Error_InvalidBorrower: u64 = 2;
    const Error_InvalidLender: u64 = 3;
    const Error_InsufficientFunds: u64 = 4;
    const Error_InvalidLoanAmount: u64 = 5;
    const Error_InvalidInterestRate: u64 = 6;
    const Error_InvalidTermLength: u64 = 7;
    const Error_LoanAlreadyExists: u64 = 8;
    const Error_NotBorrower: u64 = 9;
    const Error_NotLender: u64 = 10;
    const Error_LoanNotFound: u64 = 11;
    const Error_InvalidPaymentAmount: u64 = 12;
    const Error_LoanAlreadyPaidOff: u64 = 13;

    /* Structs */
   struct Loan has key, store {
        id: UID,
        borrower: address,
        lender: address,
        car: String, // Unique identifier or details of the car being loaned.
        car_price: u64, // Price of the car being loaned.
        loan_amount: Balance<SUI>, // Total loan amount.
        interest_rate: u64, // Annual interest rate on the loan.
        term_length: u64, // Duration of the loan in months.
        monthly_payment: u64, // Calculated monthly payment amount.
        term_start: u64, // Date the loan agreement starts.
        term_end: Option<u64>,
        full_paid_off: bool
    }

    struct Borrower has key, store {
        id: UID,
        borrower_address: address,
        escrow: Balance<SUI>,
        name: String,
        credit_score: u64,
        loan_history: Table<u64, Loan>
    }

    struct Lender has key, store {
        id: UID,
        lender_address: address,
        name: String,
        active_loans: Table<u64, Loan>
    }


    /* Functions */
    
    // Function to create a new Borrower object.
    public fun new_borrower(name: String, borrower_address: address, ctx: &mut TxContext) : Borrower {
        Borrower {
            id: object::new(ctx),
            borrower_address: borrower_address,
            escrow: balance::zero(),
            name: name,
            credit_score: 0,
            loan_history: table::new<u64, Loan>(ctx)
        }
    }

    // Function to create a new Lender object.
    public fun new_lender(name: String, lender_address: address, ctx: &mut TxContext) : Lender {
        // Check if the lender address exists.
        Lender {
            id: object::new(ctx),
            lender_address: lender_address,
            name: name,
            active_loans: table::new<u64, Loan>(ctx)
        }
    }

    // Function to create a new Loan object.
    public fun new_loan(
        borrower: &mut Borrower,
        lender: &mut Lender,
        car: String,
        car_price: u64,
        loan_amount: Balance<SUI>,
        interest_rate: u64,
        term_length: u64,
        clock: &Clock,
        record_no: u64,
        ctx: &mut TxContext
    )  {
        // Action to be performed by the lender
        assert!(tx_context::sender(ctx) == lender.lender_address, Error_NotLender);
        // Check if the loan amount is valid.
        assert!(balance::value(&loan_amount) <= car_price, Error_InvalidLoanAmount);
        // Check if the interest rate is valid.
        assert!(interest_rate > 0, Error_InvalidInterestRate);
        // Check if the term length is valid.
        assert!(term_length > 0, Error_InvalidTermLength);
        // Check if the borrower is valid.
        assert!(borrower.borrower_address != lender.lender_address, Error_InvalidBorrower);

     
            
        let loan = Loan {
            id: object::new(ctx),
            borrower: borrower.borrower_address,
            lender: lender.lender_address,
            car: car,
            car_price: car_price,
            loan_amount: loan_amount,
            interest_rate: interest_rate,
            term_length: term_length,
            monthly_payment: 0,  // Place default as 0
            term_start: clock::timestamp_ms(clock),
            term_end: none(),
            full_paid_off: false
        };

        // Add the loan to the borrower's loan history.
        table::add<u64, Loan>(&mut borrower.loan_history,record_no , loan);
   
   }

    // Add a loan to lender's active loans
    public fun add_loan_to_lender(
        lender: &mut Lender,
        loan: Loan,
        record_no: u64,
        ctx: &mut TxContext
    ) {
        // Action to be performed by the lender
        assert!(tx_context::sender(ctx) == lender.lender_address, Error_NotLender);
        // check valid loan
        assert!(loan.borrower != loan.lender, Error_InvalidLoan);
        // Check if the loan already exists.
        assert!(!table::contains(&lender.active_loans, record_no), Error_LoanAlreadyExists);
        table::add<u64, Loan>(&mut lender.active_loans, record_no, loan);
    }


    // Function to calculate the monthly payment amount.
    public fun calculate_monthly_payment(
        loan: &mut Loan,
        interest_rate: u64,
        term_length: u64
    ) {
        let loan_amount_value = balance::value(&loan.loan_amount);
        let monthly_interest_rate = interest_rate / 12;
        let monthly_interest = (loan_amount_value * monthly_interest_rate) / 100;
        let monthly_payment = (loan_amount_value + monthly_interest) / term_length;

        loan.monthly_payment = monthly_payment;


    }

    // Add Loan Amount to the Loan
    public fun add_loan_amount_to_loan(
        loan: &mut Loan,
        coin: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        // Verify lender is making the call
        assert!(tx_context::sender(ctx) == loan.lender, Error_NotLender);
        // check that is a valid lender
        assert!(loan.borrower != loan.lender, Error_InvalidLender);
        let balance_ = coin::into_balance(coin);
        balance::join(&mut loan.loan_amount, balance_);
    }

    // add coin to the escrow of the borrower
    public fun add_coin_to_escrow(
        borrower: &mut Borrower,
        coin: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        // Verify borrower is making the call
        assert!(tx_context::sender(ctx) == borrower.borrower_address, Error_NotBorrower);
        let balance_ = coin::into_balance(coin);
        balance::join(&mut borrower.escrow, balance_);
    }

    // Claim overdue payment
    public fun claim_overdue_pay(
        borrower: &mut Borrower,
        loan: &mut Loan,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
     
        // Check if the lender is making the call.
        assert!(tx_context::sender(ctx) == loan.lender, Error_NotLender);
        // Check if the loan is not already paid off.
        assert!(!loan.full_paid_off, Error_LoanAlreadyPaidOff);

        // Check if the due date has passed.
        let due_date = loan.term_start + loan.term_length;
        let current_date = clock::timestamp_ms(clock);
        assert!(current_date > due_date, Error_InsufficientFunds);

        // Calculate the overdue payment amount.
        let esc_ = balance::value(&borrower.escrow);
        let overdue_days = (current_date - due_date) / (1000 * 60 * 60 * 24);
        let overdue_payment = ((esc_ as u64) * 2 * overdue_days) / 100;

        // Transfer the overdue payment amount to the lender.
        let transfer_amnt = coin::take(&mut borrower.escrow, overdue_payment, ctx);
        transfer::public_transfer(transfer_amnt, loan.lender);
        
    }
    
    // Function to make a payment towards a loan by the borrower deduct from escrow
    public entry fun make_payment(
        borrower: &mut Borrower,
        loan: &mut Loan,
        payment_amount: u64,
        ctx: &mut TxContext
    ) {
        // Check if the borrower is making the call.
        assert!(tx_context::sender(ctx) == borrower.borrower_address, Error_NotBorrower);
        // Check if the loan is not already paid off.
        assert!(!loan.full_paid_off, Error_LoanAlreadyPaidOff);
        // Check if the payment amount is valid.
        assert!(payment_amount > 0, Error_InvalidPaymentAmount);

        // Transfer the payment amount from the borrower's escrow to the lender.
        let transfer_amnt = coin::take(&mut borrower.escrow,payment_amount , ctx);
        transfer::public_transfer(transfer_amnt, loan.lender);

     
    }

    // Mark the loan as full paid off by the borrower
    public fun mark_loan_as_paid_off(
        borrower: &mut Borrower,
        loan: &mut Loan,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if the borrower is making the call.
        assert!(tx_context::sender(ctx) == borrower.borrower_address, Error_NotBorrower);
        // Check if the loan is not already paid off.
        assert!(!loan.full_paid_off, Error_LoanAlreadyPaidOff);

        loan.full_paid_off = true;
        loan.term_end = some(clock::timestamp_ms(clock));

    }


    // Function to get the loan details.    
    public fun get_loan_details(loan: &Loan) : (String, u64, &Balance<SUI>, u64, u64, u64, u64, Option<u64>, bool) {
     
        (
            loan.car,
            loan.car_price,
            &loan.loan_amount,
            loan.interest_rate,
            loan.term_length,
            loan.monthly_payment,
            loan.term_start,
            loan.term_end,
            loan.full_paid_off
        )
    }


    // Function to get the loan amount.
    public fun get_loan_amount(loan: &Loan) : &Balance<SUI> {
        &loan.loan_amount
    }

    // Function to get the monthly payment amount.
    public fun get_monthly_payment(loan: &Loan) : u64 {
        loan.monthly_payment
    }

    // Function to get the loan term start date.
    public fun get_term_start(loan: &Loan) : u64 {
        loan.term_start
    }

    // Function to get the loan term end date.
    public fun get_term_end(loan: &Loan) : Option<u64> {
        loan.term_end
    }

    // Function to get the loan paid off status.
    public fun get_loan_paid_off(loan: &Loan) : bool {
        loan.full_paid_off
    }

    // Function to get the borrower address.
    public fun get_borrower_address(borrower: &Borrower) : address {
        borrower.borrower_address
    }

    // Function to get the lender address.
    public fun get_lender_address(lender: &Lender) : address {
        lender.lender_address
    }



    // Transaction to update the credit score of a borrower.
    public entry fun update_credit_score(
        borrower: &mut Borrower,
        lender: &Lender,
        credit_score: u64,
        ctx: &mut TxContext
    ) {
        // Lender should be the one to update the credit score.
        assert!(tx_context::sender(ctx) == lender.lender_address, Error_NotLender);
        // Check that borrower is not making this call.
        assert!(tx_context::sender(ctx) == borrower.borrower_address, Error_NotBorrower);
        borrower.credit_score = credit_score;
    }

  
  
}
