
use starknet::ContractAddress;
//defining interface for public functions, listed functions are necessary ones in erc20
#[starknet::interface]
trait Ierc20<TContractState>{
	fn init(ref self: TContractState, nm:felt252, smb:felt252);
	fn total_supply(self:@TContractState) -> u256;
	fn balance_of (self: @TContractState, account: ContractAddress) -> u256;
	fn transfer (ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
	fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
	fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
	fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
	//following two functions are not necessary in erc20, however, they are useful for safe rewriting of allowance so they're included as well
	fn increase_allowance(ref self: TContractState, spender: ContractAddress, by_value: u256) -> bool;
    fn decrease_allowance(ref self: TContractState, spender: ContractAddress, by_value: u256) -> bool;
	fn token_name(self: @TContractState) -> felt252;
    fn token_symbol(self: @TContractState) -> felt252;
    fn decimals_get(self: @TContractState) -> u8;
}

//define component for more convenient use of following code when working with erc20 contracts
#[starknet::component]
mod ERC20Component {
	use starknet::get_caller_address; 
	use starknet::ContractAddress;
    use starknet::Zeroable;
	
    #[storage]
    struct Storage {
		name: felt252,
		symbol: felt252,
		supply: u256,
		decimals: u8,
        allowance_map: LegacyMap::<(ContractAddress, ContractAddress), u256>,
		balance_map: LegacyMap::<ContractAddress, u256>,
    }
	//those structs define data types ecessary for standart erc20 event 
	#[derive(Drop, starknet::Event)]
	struct Transfer {
		#[key]
		from: ContractAddress,
		#[key]
		to:ContractAddress,
		value: u256
	}
	#[derive(Drop, starknet::Event)]
	struct Approval {
		#[key]
		owner: ContractAddress,
		#[key]
		spender: ContractAddress,
		value: u256
	}
	#[event]
	#[derive(Drop, starknet::Event)]
	enum Event {
		Transfer: Transfer,
		Approval: Approval
	}
	//nodule containing possible errors for testing
	mod Errors {
        const SENDER_ZERO: felt252 = 'Sender address is zero';
        const RECIPIENT_ZERO: felt252 = 'Recipient address is zero';
        const INVALID_BALANCE: felt252 = 'Ivalid balance';
	}
	//tell compilator that following code may be exctracted as Ierc20Impl
	#[embeddable_as(Ierc20Impl)]
	impl erc20<TContractState, +HasComponent<TContractState>> of super::Ierc20<ComponentState<TContractState>> {
		//initialize function is defined here solely for testing and ensuring proper work of constructor, it's not a part of standart erc20
		fn init(ref self: ComponentState<TContractState>, nm:felt252, smb:felt252){
			self.name.write(nm);
			self.symbol.write(smb);
			self.decimals.write(18);
		}
		//all functions untill transfer are view functions, so data is only read and input is a snapshot of a current contract state
		fn total_supply(self: @ComponentState<TContractState>) -> u256{
			self.supply.read()
		}
		fn token_name(self:@ComponentState<TContractState>) -> felt252{
			self.name.read()
		}
		fn token_symbol(self:@ComponentState<TContractState>) -> felt252{
			self.symbol.read()
		}
		fn decimals_get(self:@ComponentState<TContractState>) -> u8{
			self.decimals.read()
		}
		fn balance_of (self: @ComponentState<TContractState>, account: ContractAddress) -> u256 {
			self.balance_map.read(account)
		}
		fn allowance(self: @ComponentState<TContractState>, owner: ContractAddress, spender: ContractAddress) -> u256 {
            self.allowance_map.read((owner, spender))
        }
		//following functions are external functions
		fn transfer (ref self: ComponentState<TContractState>, recipient: ContractAddress, amount: u256) -> bool{
			let sender = get_caller_address();
			self.int_token_transfer(sender, recipient, amount);
			true
		}

		fn transfer_from (ref self: ComponentState<TContractState>, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool{
			assert(!sender.is_zero(), Errors::SENDER_ZERO);
			let caller = get_caller_address();
            let current_allowance = self.allowance_map.read((sender, caller));
			self.int_approve(sender, caller, current_allowance - amount);
			self.int_token_transfer(sender, recipient, amount);
			true
		}

		fn approve(ref self: ComponentState<TContractState>, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            self.int_approve(caller, spender, amount);
            true
        }
		
		fn increase_allowance(ref self: ComponentState<TContractState>, spender: ContractAddress, by_value: u256) -> bool{
			let caller = get_caller_address();
			self.int_approve(caller, spender, self.allowance_map.read((caller, spender)) + by_value);
			true
		}
		fn decrease_allowance(ref self: ComponentState<TContractState>, spender: ContractAddress, by_value: u256) -> bool{
			assert(!spender.is_zero(), Errors::RECIPIENT_ZERO);
			let caller = get_caller_address();
			assert(!caller.is_zero(), Errors::SENDER_ZERO);
			self.int_approve(caller, spender, self.allowance_map.read((caller, spender)) - by_value);
			true
		}

	}
	//following impl defines internal functions not accessible from outer scope
	#[generate_trait]
	impl InternalFunc<TContractState, +HasComponent<TContractState>> of InternalFuncTrait<TContractState> {
		fn int_approve (ref self: ComponentState<TContractState>, owner: ContractAddress, spender: ContractAddress, amount: u256){
			assert(!owner.is_zero(), Errors::SENDER_ZERO);
            assert(!spender.is_zero(), Errors::RECIPIENT_ZERO);
			self.allowance_map.write((owner, spender), amount);
            self.emit(Approval { owner, spender, value: amount });
		}
		fn int_token_transfer (ref self: ComponentState<TContractState>, sender: ContractAddress, recipient: ContractAddress, amount: u256
        ) {
			assert(!sender.is_zero(), Errors::SENDER_ZERO);
            assert(!recipient.is_zero(), Errors::RECIPIENT_ZERO);
            self.balance_map.write(sender, self.balance_map.read(sender) - amount);
            self.balance_map.write(recipient, self.balance_map.read(recipient) + amount);
            self.emit(Transfer { from: sender, to: recipient, value: amount });
		}
		fn mint_token (ref self: ComponentState<TContractState>, recipient: ContractAddress, amount: u256) {
			assert(!recipient.is_zero(), Errors::RECIPIENT_ZERO);
			self.supply.write(self.supply.read() + amount);
            self.balance_map.write(recipient, self.balance_map.read(recipient) + amount);
            self.emit(Transfer { from: Zeroable::zero(), to: recipient, value: amount });
		}
		fn burn_token (ref self: ComponentState<TContractState>, sender: ContractAddress, amount: u256) {
			assert(!sender.is_zero(), Errors::SENDER_ZERO);
			self.supply.write(self.supply.read() - amount);
            self.balance_map.write(sender, self.balance_map.read(sender) - amount);
            self.emit(Transfer { from: sender, to: Zeroable::zero(), value: amount });
		}
	}
}