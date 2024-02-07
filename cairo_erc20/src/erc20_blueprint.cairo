#[starknet::contract]
mod ERC20_Blueprint {
    use cairo_erc20::erc20::ERC20Component;
    use starknet::ContractAddress;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
	#[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::Ierc20Impl<ContractState>;
  	impl InternalImpl = ERC20Component::InternalFunc<ContractState>;
    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage
    }
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        initial_supply: u256,
        recipient: ContractAddress
    ) {
        self.init(name, symbol);
        self.erc20.mint_token(recipient, initial_supply);
    }
}
