# Development

## Specs and Integration Tests

```sh
# Run specs:
direnv exec . bin/specs
# which is just a helper that calls: crystal spec --verbose --error-trace
# Run specs with a different crystal version (uses asdf)
ASDF_CRYSTAL_VERSION=1.14.0 direnv exec . bin/specs

# Lint:
direnv exec . bin/lint

# Format:
direnv exec . bin/format

# Integration tests:
direnv exec . scripts/integration
direnv exec . crystal run examples/basic.cr
direnv exec . crystal run examples/capture.cr
```

To build the precompiler: `direnv exec . shards build`. The `hamlc` target in
`shard.yml` supports `--help`, `--check`, and generated method wrappers.
`--check` validates Haml structure; native Crystal compilation is still needed
to check expressions and types. Tooling can explicitly require `haml/compiler`
and call `Haml.compile` to obtain Crystal source.

## Versioned releases

The example commands here release an example version `1.x.y`. Replace `1.x.y` with the actual version number as you use them.

When preparing a new release:

1. Run specs with `direnv exec . bin/prerelease_checks`.
2. Commit the reviewed release changes.
3. Update the version number in `shard.yml` and `src/haml.cr`.
4. Update the `CHANGELOG`.
5. Commit it: `git commit -m "Update CHANGELOG for v1.x.y"`

Tag and push:

```sh
git tag -a v1.x.y -m 'haml 1.x.y'
git push --atomic origin HEAD v1.x.y
```
