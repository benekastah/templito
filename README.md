#Templito
======

Temp·li·to [temp-<strong>lee</strong>-toh]
  1. *(noun)* A small underscore.js template precompiler.
  2. *(noun)* A template burrito.

Generates javascript files for underscore.js templates.

To install:

```bash
npm install -g templito
```

For quick help:

```bash
templito -h
```

will bring up the help info:

```
Compiles underscore.js templates into javascript files.

templito source-dir out-dir [options]

Options:
  -c, --compile-style      Options include: "combined" (single file), "directory" (one file per directory) and "file" (one output file per input file).                                                                                                [default: "directory"]
  -p, --path-case          The casing for the object path part of an output function's address. If the template is source_dir/a/b/c.html, then the object path part is source_dir/a/b. Options include "camelCase", "CapitalCase",  and "snake_case".  [default: "CapitalCase"]
  -f, --function-case      The casing for the output function's name. Options are the same as for the path-case option.                                                                                                                                [default: "camelCase"]
  -e, --extension          templito will look for files with the given extension.                                                                                                                                                                      [default: ".html"]
  -k, --keep-extension     Whether or not the output files should keep the original file extension as part of its name.                                                                                                                                [default: false]
  -n, --namespace          The namespace to add your compiled template functions to.                                                                                                                                                                   [default: "App"]
  -s, --template-settings  A javascript object that will override _.templateSettings.
  -h, --help               Show this help message and exit.
  -w, --watch              Watch the source directory for changes and recompile the templates when a change is detected.
  -C, --clean              Empty the out-dir before compiling.
  -U, --unsafe-clean       Opt out of prompt before cleaning out-dir
```

More detailed documentation to come.
