# Versioning

After every 15 completed addon changes, increment the final number in the
`0.2.NN` version (for example, `0.2.40` to `0.2.41`). Keep `## Version` in
`GuildDB.toc` and `GD.version` in `Core/Runtime.lua` identical. Never reset the
final number to `01`.

Count each completed feature or fix once, regardless of how many files it
touches. Update the counter below after each completed addon change. On the
15th change, bump both version fields and reset the counter to zero.
Instruction-only or documentation-only updates do not count.

Current version: `0.2.65`
Completed addon changes toward the next version bump: **3 / 15**
