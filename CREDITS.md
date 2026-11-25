# Credits

victory-nv is a fork. Almost all of it was written by the people and projects
below, and their work is used under the GNU General Public License,
version 3 or later, the same license as this repository.

## Projects

| Project | Authors | License | How it is used here |
|---|---|---|---|
| [VIctory](https://github.com/Marvisak/VIctory) | Marvisak and contributors | GPL-3.0-or-later | The base: loader, runtime services, D3D12 back end, shader recompiler, tooling |
| [victory-fork](https://github.com/fxceless/victory-fork) | fxceless and contributors | GPL-3.0-or-later | Merged: rendering, streaming, shadow-memory and relay work |
| [victory-amd](https://github.com/myokex/victory-amd) | myokex | GPL-3.0-or-later | Merged: texture-view, dispatch-splitting, pipeline-list and view-clamp fixes |
| [VItoriaBr](https://github.com/uiliannn/VItoriaBr) | uiliannn | GPL-3.0-or-later | Consulted: array-texture LOD queries, shadow-buffer states, computed descriptor addresses |
| [JMAN730/victory](https://github.com/JMAN730/victory) | JMAN730 | GPL-3.0-or-later | Consulted for comparison while profiling |
| [XCL](https://github.com/ivall/xcl) | ivall and contributors | GPL-2.0-only | Behavioural reference only. No code copied |

## Contributors

These people authored commits in the history this repository was built from,
listed alphabetically. Per-commit authorship lives in the upstream
repositories above.

- 9hvn9yt2vk-netizen
- Abdellah K.
- Advait Palve
- AlanQiang0418
- alessiodeia
- Andrea Casale
- artor410
- BaggyALPHA
- Carlos Sant'Anna
- cxccxc
- Dathinel
- Duff
- EatCodeSleep2
- Enzo Souza Duarte
- Exorion
- FIocker
- fuzeofficial
- fxceless
- Henrique Bueno
- hophaver
- ifBars
- ismailchaka1
- itsRevela
- Jeremy Goldberg
- julio
- KoLolX3
- lameloball2813-ui
- LaunchDoesntCode
- lordon1a
- Louis Faust
- LUIS LARIOS
- Luiz Neves
- Lyrnc
- Manuel Pérez
- Maraco91
- marquezini
- Marvis
- meower
- myokex
- Nostyxx
- oddiums
- Pedro Fortunato
- quaternion
- r4.
- raffclar
- Saitken91
- tedin7
- TG0000
- Vanthys
- Yaekai
- ZazaJr24

victory-nv's own changes (NVIDIA performance work, the automated benchmark)
are by mravatins, developed with [Claude Code](https://claude.com/claude-code).

## Third-party crates

Rust dependencies are listed in `Cargo.toml` and `Cargo.lock`, each under
its own license (mostly MIT/Apache-2.0, zlib for the deflate crate).
`cargo tree` or `cargo about` produce the full list.

## Format data

`crates/victory-formats/src/bcpack-tables.bin` holds the constant tables of
the BCPack compression format. A stream cannot be decoded without them. They are
not covered by this repository's license; see
[docs/asset-policy.md](docs/asset-policy.md#the-one-exception).

If you are missing from this file or credited wrongly, open an issue or a pull
request.
