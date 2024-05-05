module Secure_wheels::wheel {
    use sui::transfer;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID, ID};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{TxContext, sender};

    use std::string::{String};
    use std::option::{Option, none};

    use Secure_wheels::usdc::{USDC};

    // Constants
    const Error_InvalidBorrower: u64 = 0;
    const Error_InsufficientFunds: u64 = 1;
    const Error_LoanAlreadyPaidOff: u64 = 2;

    /* Structs */
   struct Loan has key, store {
        id: UID,
        borrower: Option<address>,
        lender: address,
        car: String, // Unique identifier or details of the car being loaned.
        car_price: u64, // Price of the car being loaned.
        loan_amount: Balance<USDC>, // Total loan amount.
        interest_rate: u64, // Annual interest rate on the loan.
        term_length: u64, // Duration of the loan in months.
        monthly_payment: u64, // Calculated monthly payment amount.
        term_start: u64, // Date the loan agreement starts.
        term_end: Option<u64>,
        full_paid_off: bool
    }

    struct Borrower has key, store {
        id: UID,
        loan: ID,
        owner: address,
        balance: Balance<SUI>,
        depth: u64,
        deposit: u64,
        active: bool
    }

    struct Lender has key, store {
        id: UID,
        loan: ID,
        lender_address: address,
        value: u64
    }

    // Function to create a new Lender object.
    public fun new_lender(
        lender_address: address, 
        car: String,
        car_price: u64,
        interest_rate: u64,
        term_length: u64,
        coin: Coin<USDC>,
        clock: &Clock,
        ctx: &mut TxContext
        ) : (Lender, Loan) {
        let id_ = object::new(ctx);
        let inner_ = object::uid_to_inner(&id_);
        // convert coin to balance
        let amount = coin::value(&coin);
        let balance_ = coin::into_balance(coin);
        let loan = Loan {
            id: id_,
            borrower: none(),
            lender: sender(ctx),
            car: car,
            car_price: car_price,
            loan_amount: balance_,
            interest_rate: interest_rate,
            term_length: term_length,
            monthly_payment: 0,  // Place default as 0
            term_start: clock::timestamp_ms(clock),
            term_end: none(),
            full_paid_off: false
        };

        calculate_monthly_payment(&mut loan, interest_rate, term_length);

        let lender = Lender {
            id: object::new(ctx),
            loan: inner_,
            lender_address: lender_address,
            value: amount
        };
        (lender, loan)
    }

    public fun get_loan(self: &mut Loan, coin: Coin<SUI>, ctx: &mut TxContext) : (Borrower, Coin<USDC>) {
        let amount = coin::value(&coin);
        assert!(amount >= balance::value(&self.loan_amount), Error_InsufficientFunds);
        let balance_ = coin::into_balance(coin);
        let id_ = object::id(self);

        let usdc_ = balance::withdraw_all(&mut self.loan_amount);
        let coin_ = coin::from_balance(usdc_, ctx);
        let depth_ = coin::value(&coin_);

        let borrower = Borrower {
            id: object::new(ctx),
            loan: id_,
            owner: sender(ctx),
            balance: balance_,
            depth: depth_,
            deposit: amount,
            active: true
        };
        (borrower, coin_)
    }

    // Add Loan Amount to the Loan
    public fun pay_loan(
        loan: &mut Loan,
        borrower: &mut Borrower,
        coin: Coin<USDC>,
    ) {
        assert!(borrower.loan == object::id(loan), Error_InvalidBorrower);
        let balance_ = coin::into_balance(coin);
        let amount = balance::value(&balance_);
        // decrease the depth
        borrower.depth = borrower.depth - amount;
        // join the balance 
        balance::join(&mut loan.loan_amount, balance_);
    }
    // Claim overdue payment
    public fun claim_overdue_pay(
        borrower: &mut Borrower,
        loan: &mut Loan,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if the lender is making the call.
        assert!(borrower.loan == object::id(loan), Error_InvalidBorrower);
        // Check if the loan is not already paid off.
        assert!(!loan.full_paid_off, Error_LoanAlreadyPaidOff);
        // Check if the due date has passed.
        let due_date = loan.term_start + loan.term_length;
        let current_date = clock::timestamp_ms(clock);
        assert!(current_date > due_date, Error_InsufficientFunds);

        // Calculate the overdue payment amount.
        let esc_ = balance::value(&borrower.balance);
        let overdue_days = (current_date - due_date) / (1000 * 60 * 60 * 24);
        let overdue_payment = ((esc_ as u64) * 2 * overdue_days) / 100;

        // Transfer the overdue payment amount to the lender.
        let transfer_amnt = coin::take(&mut borrower.balance, overdue_payment, ctx);
        transfer::public_transfer(transfer_amnt, loan.lender);
    }

    public fun borrower_withdraw(borrower: &mut Borrower, amount: u64, ctx: &mut TxContext) : Coin<SUI> {
        assert!(amount < borrower.depth, Error_InsufficientFunds);
        let coin_ = coin::take(&mut borrower.balance, amount, ctx);
        coin_
    }

    public fun lender_withdraw(cap: &Lender, loan: &mut Loan, amount: u64, ctx: &mut TxContext) : Coin<USDC> {
        assert!(cap.loan == object::id(loan), Error_InvalidBorrower);
        let coin_ = coin::take(&mut loan.loan_amount, amount, ctx);
        coin_
    }
    
    // Function to get the loan details.    
    public fun get_loan_details(loan: &Loan) : (String, u64, u64, u64, u64, u64, u64, Option<u64>, bool) {
        (
            loan.car,
            loan.car_price,
            balance::value(&loan.loan_amount),
            loan.interest_rate,
            loan.term_length,
            loan.monthly_payment,
            loan.term_start,
            loan.term_end,
            loan.full_paid_off
        )
    }

    // Function to calculate the monthly payment amount.
    fun calculate_monthly_payment(
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

    // Function to get the loan amount.
    public fun get_loan_amount(loan: &Loan) : u64 {
        balance::value(&loan.loan_amount)    
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

    // Function to get the lender address.
    public fun get_lender_address(lender: &Lender) : address {
        lender.lender_address
    }
}
