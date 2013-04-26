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
templito
```

will bring up the help info:

```
Compiles underscore.js templates into javascript files. Takes one required argument that represents the source directory of the templates you want to compile.

Options:
  -o, --out-dir            The directory where _templito will put the compiled template files.                                                           [default: "<source-dir>/_compiled"]
  -c, --compile-style      Options include: "combined" (single file), "directory" (one file per directory) and "file" (one output file per input file).  [default: "directory"]
  -e, --extension          _templito will look for files with the given extension.                                                                       [default: "html"]
  -n, --namespace          The namespace to add your compiled template functions to.                                                                     [default: "App"]
  -s, --template-settings  A javascript object that will override _.templateSettings.
  -h, --help               Show this help message and exit.
  -w, --watch              Watch the source directory for changes and recompile the templates when a change is detected.
  -C, --clean              Empty the out-dir before compiling.
  -U, --unsafe-clean       Opt out of prompt before cleaning out-dir
```

More detailed documentation to come.
