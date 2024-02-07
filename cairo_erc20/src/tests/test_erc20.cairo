use cairo_erc20::erc20::ERC20Component;
use cairo_erc20::erc20_blueprint::ERC20_Blueprint;
use cairo_erc20::erc20::ERC20Component::{Approval, Transfer};
use cairo_erc20::erc20::ERC20Component::{Ierc20Impl, InternalFunc};
use starknet::contract_address_const;
use starknet::ContractAddress;
use starknet::testing;
use core::fmt::{Debug, Formatter, Error};

//
// Setup
//
const NAME: felt252 = 'NAME';
const SYMBOL: felt252 = 'SYMBOL';
const DECIMALS: u8 = 18_u8;
const SUPPLY: u256 = 2000;
const VALUE: u256 = 300;
fn ZERO() -> ContractAddress {
    contract_address_const::<0>()
}
fn OWNER() -> ContractAddress {
    contract_address_const::<'OWNER'>()
}
fn SPENDER() -> ContractAddress {
    contract_address_const::<'SPENDER'>()
}

fn RECIPIENT() -> ContractAddress {
    contract_address_const::<'RECIPIENT'>()
}
mod utils {
    use starknet::ContractAddress;
    use starknet::testing;
    fn pop_log<T, +Drop<T>, +starknet::Event<T>>(address: ContractAddress) -> Option<T> {
        let (mut keys, mut data) = testing::pop_log_raw(address)?;

        // Remove the event ID from the keys
        keys.pop_front();

        let ret = starknet::Event::deserialize(ref keys, ref data);
        assert!(data.is_empty(), "Event has extra data");
        assert!(keys.is_empty(), "Event has extra keys");
        ret
    }

    /// Asserts that `expected_keys` exactly matches the indexed keys from `event`.
    ///
    /// `expected_keys` must include all indexed event keys for `event` in the order
    /// that they're defined.
    fn assert_indexed_keys<T, +Drop<T>, +starknet::Event<T>>(event: T, expected_keys: Span<felt252>) {
        let mut keys = array![];
        let mut data = array![];

        event.append_keys_and_data(ref keys, ref data);
        assert!(expected_keys == keys.span());
    }
    
    fn assert_no_events_left(address: ContractAddress) {
        assert!(testing::pop_log_raw(address).is_none(), "Events remaining on queue");
    }

    fn drop_event(address: ContractAddress) {
        testing::pop_log_raw(address);
    }

}
trait SerializedAppend<T> {
    fn append_serde(ref self: Array<felt252>, value: T);
}

impl SerializedAppendImpl<T, impl TSerde: Serde<T>, impl TDrop: Drop<T>> of SerializedAppend<T> {
    fn append_serde(ref self: Array<felt252>, value: T) {
        value.serialize(ref self);
    }
}
type ComponentState = ERC20Component::ComponentState<ERC20_Blueprint::ContractState>;

fn COMPONENT_STATE() -> ComponentState {
    ERC20Component::component_state_for_testing()
}

fn setup() -> ComponentState {
    let mut state = COMPONENT_STATE();
    state.init(NAME, SYMBOL);
    state.mint_token(OWNER(), SUPPLY);
    utils::drop_event(ZERO());
    state
}

//
// initializer & constructor
//

#[test]
fn test_constructor() {
    let mut state = COMPONENT_STATE();
    state.init(NAME, SYMBOL);

    assert_eq!(state.token_name(), NAME);
    assert_eq!(state.token_symbol(), SYMBOL);
    assert_eq!(state.decimals_get(), DECIMALS);
    assert_eq!(state.total_supply(), 0);
}

//
// Getters
//

#[test]
fn test_total_supply() {
    let mut state = COMPONENT_STATE();
    state.mint_token(OWNER(), SUPPLY);
    assert_eq!(state.total_supply(), SUPPLY);
}

#[test]
fn test_balance_of() {
    let mut state = COMPONENT_STATE();
    state.mint_token(OWNER(), SUPPLY);
    assert_eq!(state.balance_of(OWNER()), SUPPLY);
}


#[test]
fn test_allowance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.approve(SPENDER(), VALUE);

    let allowance = state.allowance(OWNER(), SPENDER());
    assert_eq!(allowance, VALUE);
}

//
// approve & int_approve
//

#[test]
fn test_approve() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    assert!(state.approve(SPENDER(), VALUE));

    assert_only_event_approval(OWNER(), SPENDER(), VALUE);

    let allowance = state.allowance(OWNER(), SPENDER());
    assert_eq!(allowance, VALUE);
}

#[test]
#[should_panic]
fn test_approve_from_zero() {
    let mut state = setup();
    state.approve(SPENDER(), VALUE);
}

#[test]
#[should_panic]
fn test_approve_to_zero() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.approve(ZERO(), VALUE);
}

#[test]
fn test_int_approve() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.int_approve(OWNER(), SPENDER(), VALUE);

    assert_only_event_approval(OWNER(), SPENDER(), VALUE);

    let allowance = state.allowance(OWNER(), SPENDER());
    assert_eq!(allowance, VALUE);
}

#[test]
#[should_panic]
fn test_int_approve_from_zero() {
    let mut state = setup();
    state.int_approve(ZERO(), SPENDER(), VALUE);
}

#[test]
#[should_panic]
fn test_int_approve_to_zero() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.int_approve(OWNER(), ZERO(), VALUE);
}

//
// transfer & int_token_transfer
//

#[test]
fn test_transfer() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.transfer(RECIPIENT(), VALUE);

    assert_only_event_transfer(OWNER(), RECIPIENT(), VALUE);
    assert_eq!(state.balance_of(RECIPIENT()), VALUE);
    assert_eq!(state.balance_of(OWNER()), SUPPLY - VALUE);
    assert_eq!(state.total_supply(), SUPPLY);
}

#[test]
#[should_panic]
fn test_transfer_not_enough_balance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());

    let balance_plus_one = SUPPLY + 1;
    state.transfer(RECIPIENT(), balance_plus_one);
}

#[test]
#[should_panic]
fn test_transfer_from_zero() {
    let mut state = setup();
    state.transfer(RECIPIENT(), VALUE);
}

#[test]
#[should_panic]
fn test_transfer_to_zero() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.transfer(ZERO(), VALUE);
}

#[test]
fn test_int_token_transfer() {
    let mut state = setup();

    state.int_token_transfer(OWNER(), RECIPIENT(), VALUE);

    assert_only_event_transfer(OWNER(), RECIPIENT(), VALUE);
    assert_eq!(state.balance_of(RECIPIENT()), VALUE);
    assert_eq!(state.balance_of(OWNER()), SUPPLY - VALUE);
    assert_eq!(state.total_supply(), SUPPLY);
}

#[test]
#[should_panic]
fn test_int_token_transfer_not_enough_balance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());

    let balance_plus_one = SUPPLY + 1;
    state.int_token_transfer(OWNER(), RECIPIENT(), balance_plus_one);
}

#[test]
#[should_panic]
fn test_int_token_transfer_from_zero() {
    let mut state = setup();
    state.int_token_transfer(ZERO(), RECIPIENT(), VALUE);
}

#[test]
#[should_panic]
fn test_int_token_transfer_to_zero() {
    let mut state = setup();
    state.int_token_transfer(OWNER(), ZERO(), VALUE);
}

//
// transfer_from
//

#[test]
fn test_transfer_from() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.approve(SPENDER(), VALUE);
    utils::drop_event(ZERO());

    testing::set_caller_address(SPENDER());
    assert!(state.transfer_from(OWNER(), RECIPIENT(), VALUE));

    assert_event_approval(OWNER(), SPENDER(), 0);
    assert_only_event_transfer(OWNER(), RECIPIENT(), VALUE);

    let allowance = state.allowance(OWNER(), SPENDER());
    assert_eq!(allowance, 0);

    assert_eq!(state.balance_of(RECIPIENT()), VALUE);
    assert_eq!(state.balance_of(OWNER()), SUPPLY - VALUE);
    assert_eq!(state.total_supply(), SUPPLY);
}

#[test]
#[should_panic]
fn test_transfer_from_greater_than_allowance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.approve(SPENDER(), VALUE);

    testing::set_caller_address(SPENDER());
    let allowance_plus_one = VALUE + 1;
    state.transfer_from(OWNER(), RECIPIENT(), allowance_plus_one);
}

#[test]
#[should_panic]
fn test_transfer_from_to_zero_address() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.approve(SPENDER(), VALUE);

    testing::set_caller_address(SPENDER());
    state.transfer_from(OWNER(), ZERO(), VALUE);
}

#[test]
#[should_panic]
fn test_transfer_from_from_zero_address() {
    let mut state = setup();
    state.transfer_from(ZERO(), RECIPIENT(), VALUE);
}

//
// increase_allowance
//

#[test]
fn test_increase_allowance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.approve(SPENDER(), VALUE);
    utils::drop_event(ZERO());

    assert!(state.increase_allowance(SPENDER(), VALUE));

    assert_only_event_approval(OWNER(), SPENDER(), VALUE * 2);

    let allowance = state.allowance(OWNER(), SPENDER());
    assert_eq!(allowance, VALUE * 2);
}

#[test]
#[should_panic]
fn test_increase_allowance_to_zero_address() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.increase_allowance(ZERO(), VALUE);
}

#[test]
#[should_panic]
fn test_increase_allowance_from_zero_address() {
    let mut state = setup();
    state.increase_allowance(SPENDER(), VALUE);
}

//
// decrease_allowance 
//

#[test]
fn test_decrease_allowance() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.approve(SPENDER(), VALUE);
    utils::drop_event(ZERO());

    assert!(state.decrease_allowance(SPENDER(), VALUE));

    assert_only_event_approval(OWNER(), SPENDER(), 0);

    let allowance = state.allowance(OWNER(), SPENDER());
    assert_eq!(allowance, 0);
}

#[test]
#[should_panic(expected: ('Recipient address is zero',))]
fn test_decrease_allowance_to_zero_address() {
    let mut state = setup();
    testing::set_caller_address(OWNER());
    state.decrease_allowance(ZERO(), VALUE);
}

#[test]
#[should_panic]
fn test_decrease_allowance_from_zero_address() {
    let mut state = setup();
    state.decrease_allowance(SPENDER(), VALUE);
}

//
// mint_token
//

#[test]
fn test__mint() {
    let mut state = COMPONENT_STATE();
    state.mint_token(OWNER(), VALUE);

    assert_only_event_transfer(ZERO(), OWNER(), VALUE);
    assert_eq!(state.balance_of(OWNER()), VALUE);
    assert_eq!(state.total_supply(), VALUE);
}

#[test]
#[should_panic]
fn test__mint_to_zero() {
    let mut state = COMPONENT_STATE();
    state.mint_token(ZERO(), VALUE);
}

//
// burn_token
//

#[test]
fn test_burn() {
    let mut state = setup();
    state.burn_token(OWNER(), VALUE);

    assert_only_event_transfer(OWNER(), ZERO(), VALUE);
    assert_eq!(state.total_supply(), SUPPLY - VALUE);
    assert_eq!(state.balance_of(OWNER()), SUPPLY - VALUE);
}

#[test]
#[should_panic]
fn test_burn_from_zero() {
    let mut state = setup();
    state.burn_token(ZERO(), VALUE);
}

//
// Helpers
//



fn assert_only_event_approval(owner: ContractAddress, spender: ContractAddress, value: u256) {
    assert_event_approval(owner, spender, value);
    utils::assert_no_events_left(ZERO());
}

fn assert_event_approval(owner: ContractAddress, spender: ContractAddress, value: u256) {
    let event = utils::pop_log::<Approval>(ZERO()).unwrap();
    assert_eq!(event.owner, owner);
    assert_eq!(event.spender, spender);
    assert_eq!(event.value, value);

    // Check indexed keys
    let mut indexed_keys = array![];
    indexed_keys.append_serde(owner);
    indexed_keys.append_serde(spender);
    utils::assert_indexed_keys(event, indexed_keys.span())
}
fn assert_event_transfer(from: ContractAddress, to: ContractAddress, value: u256) {
    let event = utils::pop_log::<Transfer>(ZERO()).unwrap();
    assert_eq!(event.from, from);
    assert_eq!(event.to, to);
    assert_eq!(event.value, value);

    // Check indexed keys
    let mut indexed_keys = array![];
    indexed_keys.append_serde(from);
    indexed_keys.append_serde(to);
    utils::assert_indexed_keys(event, indexed_keys.span());
}


fn assert_only_event_transfer(from: ContractAddress, to: ContractAddress, value: u256) {
    assert_event_transfer(from, to, value);
    utils::assert_no_events_left(ZERO());
}