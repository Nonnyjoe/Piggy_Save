use starknet::ContractAddress;
#[starknet::interface]
trait IERC20<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface] 
trait piggyBankTrait<TContractState> {
    fn deposit(ref self: TContractState, _amount: u128);
    fn withdraw(ref self: TContractState, _amount: u128);
    fn get_balance(self: @TContractState) -> u128;
}

#[starknet::contract]
mod piggyBank {
    use starknet::{get_caller_address, ContractAddress, get_contract_address, Zeroable};
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};
    use core::traits::Into;
    
    #[storage]
    struct Storage {
        owner: ContractAddress,
        token: IERC20Dispatcher,
        balance: u128,
        withdrawalCondition: target,
    }

    #[derive(Drop, Serde, starknet::Store)]
    enum target {
        blockTime: felt252,
        amount: u128,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdraw: Withdraw
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        #[key]
        from: ContractAddress,
        #[key]
        Amount: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        #[key]
        to: ContractAddress,
        #[key]
        Amount: u128,
        #[key]
        ActualAmount: u128,
    }

    #[constructor]
    fn constructor(ref self: ContractState, _owner: ContractAddress, _withdrawalCondition: target, _token: ContractAddress) {
        assert(!_owner.is_zero(), 'Invalid owner');
        assert(!_token.is_zero(), 'Invalid Token');
        self.owner.write(_owner);
        self.withdrawalCondition.write(_withdrawalCondition);
        self.token.write(super::IERC20Dispatcher{contract_address: _token});
    }

    #[external(v0)]
    impl piggyBankImpl of super::piggyBankTrait<ContractState> {
        fn deposit(ref self: ContractState, _amount: u128) {
            let caller: ContractAddress = get_caller_address();
            let this: ContractAddress = get_contract_address();
            let currentBalance: u128 = self.balance.read();

            self.balance.write(currentBalance + _amount);

            self.token.read().transfer_from(caller, this, _amount.into());

            self.emit(Deposit { from: caller, Amount: _amount});
        }

        fn withdraw(ref self: ContractState, _amount: u128) {
            let caller: ContractAddress = get_caller_address();
            let this: ContractAddress = get_contract_address();
            let currentBalance: u128 = self.balance.read();
            assert(caller == self.owner.read(), 'UnAuthorized caller');
            assert(self.balance.read() >= _amount, 'Insufficient balance');

            let mut new_amount: u128 = 0;
            match self.withdrawalCondition.read() {
                target::blockTime(x) => new_amount = self.verifyBlockTime(x, _amount),
                target::amount(x) => new_amount = self.verifyTargetAmount(x, _amount),
            };
            
            self.balance.write(currentBalance - _amount);
            self.token.read().transfer(caller, new_amount.into());

            self.emit(Withdraw { to: caller, Amount: _amount, ActualAmount: new_amount});
        }

        fn get_balance(self: @ContractState) -> u128 {
            self.balance.read()
        }
    }

    #[generate_trait]
    impl Private of PrivateTrait {
        fn verifyBlockTime(self: @ContractState, blockTime: felt252, withdrawalAmount: u128) -> u128 {
            withdrawalAmount
        }

        fn verifyTargetAmount(self: @ContractState, targetAmount: u128, withdrawalAmount: u128) -> u128 {
            withdrawalAmount
        }

        fn getDetails(self: @ContractState) -> (ContractAddress, ContractAddress, u128) {
            let caller: ContractAddress = get_caller_address();
            let this: ContractAddress = get_contract_address();
            let currentBalance: u128 = self.balance.read();
            (caller, this, currentBalance)
        }
    }



}