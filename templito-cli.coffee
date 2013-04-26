path = require 'path'
optimist = require 'optimist'
watch = require 'node-watch'
log = require('./util').log
templito = require './'

argv = require('optimist')
.usage('Compiles underscore.js templates into javascript files. Takes ' +
       'one required argument that represents the source directory of the ' +
       'templates you want to compile.')
.options(
  o:
    alias: 'out-dir'
    describe: 'The directory where _templito will put the compiled template files.'
    default: '<source-dir>/_compiled'
  c:
    alias: 'compile-style'
    describe: 'Options include: "combined" (single file), "directory" (one ' +
              'file per directory) and "file" (one output file per input ' +
              'file).'
    default: 'directory'
  e:
    alias: 'extension'
    describe: '_templito will look for files with the given extension.'
    default: 'html'
  n:
    alias: 'namespace'
    describe: 'The namespace to add your compiled template functions to.'
    default: 'App'
  # p:
  #   alias: 'no-precompile'
  #   describe: 'If true, underscore compilation of templates will happen at ' +
  #             'runtime.'
  s:
    alias: 'template-settings'
    describe: 'A javascript object that will override _.templateSettings.'
  h:
    alias: 'help'
    describe: 'Show this help message and exit.'
  w:
    alias: 'watch'
    describe: 'Watch the source directory for changes and recompile the ' +
              'templates when a change is detected.'
  C:
    alias: 'clean'
    describe: 'Empty the out-dir before compiling.'
  U:
    alias: 'unsafe-clean'
    describe: 'Opt out of prompt before cleaning out-dir'
).argv

show_help = (msg) ->
  optimist.showHelp()
  console.error msg if msg
  process.exit msg ? 1 : 0

if argv.help
  show_help()

# Underscorify hyphenated keys
re_hyphen = /(\w*)\-(\w*)/g
for key, value of argv
  if re_hyphen.test key
    _key = key.replace re_hyphen, '$1_$2'
    argv[_key] = value

argv.source_dir = argv._[0]
if not argv.source_dir
  show_help 'Missing required argument'

# Make sure the out_dir default is within the context of source_dir
argv.out_dir = argv.out_dir.replace /<source\-dir>/, argv.source_dir

compile = ->
  log 'Compiling templates...'
  templito.compile argv
compile()

if argv.watch
  timeout = null
  watch argv.source_dir, (filename) ->
    out_dir_match = filename.match argv.out_dir
    if not out_dir_match or out_dir_match.index isnt 0
      console.log()
      log "Detected a change in #{JSON.stringify filename}"
      clearTimeout timeout
      timeout = setTimeout compile, 500
