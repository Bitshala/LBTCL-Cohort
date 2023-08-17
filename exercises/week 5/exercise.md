# Problem Statement

Relative timelocks are used to make input-specific locks. Using relative timelock, a transaction can be locked up to a certain number of blocks since the block in which the input it is referring to has been mined.

The exercise below demonstrates using a relative timelock spend.

### Write a bash script to:

#### Setup a relative timelock

1. Create two wallets: `Miner`, `Alice`.
2. Fund the wallets by generating some blocks for `Miner` and sending some coins to `Alice`.
3. Confirm the transaction and assert that `Alice` has a positive balance.
4. Create a transaction where `Alice` pays 10 BTC back to `Miner`, but with a relative timelock of 10 blocks.
5. Report in the terminal output what happens when you try to broadcast the 2nd transaction.
#### Spend from relative timeLock

1. Generate 10 more blocks.
2. Broadcast the 2nd transaction. Confirm it by generating one more block.
3. Report Balance of `Alice`.

## Submission

- Create a bash script with your solution for the entire exercise.
- Save the script in the provided solution folder with the name `<your-discord-name>.sh`.
- Create a pull request to add the new file to the solution folder.
- The script must include all the exercise steps, but you can also add your own scripting improvements or enhancements.
- The best script of the week will be showcased in the discord `shell-showcase` channel.

## Resources

- Useful bash script examples: [https://linuxhint.com/30_bash_script_examples/](https://linuxhint.com/30_bash_script_examples/)
- Useful `jq` examples: [https://www.baeldung.com/linux/jq-command-json](https://www.baeldung.com/linux/jq-command-json)
- Use `jq` to create JSON: [https://spin.atomicobject.com/2021/06/08/jq-creating-updating-json/](https://spin.atomicobject.com/2021/06/08/jq-creating-updating-json/)
- Creating a pull request via a web browser: [https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request)
