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
    use core::option::OptionTrait;
    use core::traits::TryInto;
    use starknet::{get_caller_address, ContractAddress, get_contract_address, Zeroable, get_block_timestamp};
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};
    use core::traits::Into;
    use piggy_bank::ownership_component::ownable_component;
    component!(path: ownable_component, storage: ownable, event: OwnableEvent);


    #[abi(embed_v0)]
    impl OwnableImpl = ownable_component::Ownable<ContractState>;
    impl OwnableInternalImpl = ownable_component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        token: IERC20Dispatcher,
        manager: ContractAddress,
        balance: u128,
        withdrawalCondition: target,
        #[substorage(v0)]
        ownable: ownable_component::Storage
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
        Withdraw: Withdraw,
        PaidProcessingFee: PaidProcessingFee,
        OwnableEvent: ownable_component::Event
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

    #[derive(Drop, starknet::Event)]
    struct PaidProcessingFee {
        #[key]
        from: ContractAddress,
        #[key]
        Amount: u128,
    }

    mod Errors {
        const Address_Zero_Owner: felt252 = 'Invalid owner';
        const Address_Zero_Token: felt252 = 'Invalid Token';
        const UnAuthorized_Caller: felt252 = 'UnAuthorized caller';
        const Insufficient_Balance: felt252 = 'Insufficient balance';
    }

    #[constructor]
    fn constructor(ref self: ContractState, _owner: ContractAddress, _token: ContractAddress, _manager: ContractAddress) {
        assert(!_owner.is_zero(), Errors::Address_Zero_Owner);
        assert(!_token.is_zero(), Errors::Address_Zero_Token);
        self.ownable.owner.write(_owner);
        self.withdrawalCondition.write(target::amount(10000000000000000000));
        self.token.write(super::IERC20Dispatcher{contract_address: _token});
        self.manager.write(_manager);
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
            self.ownable.assert_only_owner();
            assert(self.balance.read() >= _amount, Errors::Insufficient_Balance);

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
        fn verifyBlockTime(ref self: ContractState, blockTime: felt252, withdrawalAmount: u128) -> u128 {
            if (get_block_timestamp() > blockTime.try_into().unwrap()) {
                return self.processWithdrawalFee(withdrawalAmount);
            } else {
                return withdrawalAmount;
            }
        }

        fn verifyTargetAmount(ref self: ContractState, targetAmount: u128, withdrawalAmount: u128) -> u128 {
            if (self.balance.read() < targetAmount) {
                return self.processWithdrawalFee(withdrawalAmount);
            } else {
                return withdrawalAmount;
            }
        }

        fn processWithdrawalFee(ref self: ContractState, withdrawalAmount: u128) -> u128 {
            let withdrawalCharge: u128 = ((withdrawalAmount * 10) / 100);
            self.balance.write(self.balance.read() - withdrawalCharge);
            self.token.read().transfer(self.manager.read(), withdrawalCharge.into());
            self.emit(PaidProcessingFee{from: get_caller_address(), Amount: withdrawalCharge});
            return withdrawalAmount - withdrawalCharge;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{piggyBankTrait, piggyBank, piggyBankTraitDispatcher, piggyBankTraitDispatcherTrait};
    use starknet::class_hash::Felt252TryIntoClassHash;
    use starknet::{
        deploy_syscall, ContractAddress, get_caller_address, get_contract_address,
        contract_address_const
    };
    use serde::Serde;
    use starknet::testing::{set_caller_address, set_contract_address};
    
    fn deploy(owner: ContractAddress,  token: ContractAddress, manager: ContractAddress) -> piggyBankTraitDispatcher {
        let mut calldata = ArrayTrait::new();
        owner.serialize(ref calldata);
        // target.serialize(ref calldata);
        token.serialize(ref calldata);
        manager.serialize(ref calldata);

        let (contract_address, _) = deploy_syscall(
            piggyBank::TEST_CLASS_HASH.try_into().unwrap(), 0, calldata.span(), false
        )
            .unwrap();

        piggyBankTraitDispatcher{contract_address}
    }

    #[test]
    #[available_gas(2000000000)]
    fn test_deploy() {
        let owner: ContractAddress = get_contract_address();
        // let target: super::piggyBank::target = super::piggyBank::target::amount(10000000000000000000);
        let token: ContractAddress = get_contract_address();
        let manager: ContractAddress = get_contract_address();
        let contract = deploy(owner, token, manager);
    }

    #[test]
    fn add_two_and_two() {
        let result = 2 + 2;
        assert(result == 4, 'result is not 4');
    }

    #[test]
    fn add_three_and_two() {
        let result = 3 + 2;
        assert(result == 5, 'result is not 5');
    }
}