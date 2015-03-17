
events = require 'events'
fs = require 'fs'
path = require 'path'
utilities = require './utilities'
Q = require 'q'

try
  _ = require 'underscore'
catch e
  console.warn 'Underscore could not be loaded. Precompiling templates will '+
               'not work until this problem is resolved.', e


###
# @class OutFile
###
class OutFile
  header = null
  footer = null

  constructor: (_path, @options) ->

    @header = @options.header
    @footer = @options.footer
    @path = _path

    @defaulted_object_paths = []

    @queued_appends = []
    @ready = false
    @disabled = true

    # Make all the needed directories for this file.
    utilities.mkdirp path.dirname(@path)
    .then () =>
      if @header
        utilities.contents @header
        .then (c) =>
          @write c
      else
        Q.resolve()
    .then () =>
      # we only enable the queue at all once we've opened the file
      # and have written our header
      @disabled = false
      @start_queue()
    .catch (err) =>
      utilities.error err
      if err.stack
        utilities.error err.stack
      Q.reject(err)

    return undefined # to supress annoying vim warning

  run_queued_appends: =>
    if not @disabled and @ready and @queued_appends.length > 0
      @ready = false
      # take the queue
      cur_appends = @queued_appends
      @queued_appends = []
      # sequence them!
      cur_appends.reduce(Q.when, Q.resolve())
      .then () =>
        # continue!
        @start_queue()
    else
      # ready for more
      @ready = true
      Q.resolve()

  start_queue: =>
    @ready = true
    Q.resolve()
    .then () =>
      @run_queued_appends()

  append_queue: (fn) =>
    @queued_appends.push fn
    # start it if it's not already running
    @run_queued_appends()


  default_object_path: (object_paths...) ->
    defaults = []
    for object_path in object_paths
        parts = object_path.split '.'
        _parts = [parts[0]]
        # Don't initialize the namespace. If the namespace doesn't exist
        # before the templates are included, that's an error.
        for part in parts.slice 1
          _parts.push part
          part = _parts.join '.'
          if part not in @defaulted_object_paths
            _default = "#{part} || (#{part} = {});"
            defaults.push _default
            @defaulted_object_paths.push part
    defaults = defaults.join '\n'
    if defaults
      @append defaults + '\n\n'
    else
      Q.resolve(null)

  append_template: (name, fn) ->
    object_path = name.split('.').slice(0, -1).join('.')
    @default_object_path object_path
    .then =>
      @append "#{name} = #{fn};\n\n"

  append: (text) =>
    do_append = () =>
      utilities.append @path, text, @file_options
      .catch (err) =>
        utilities.error "Error appending to #{@path}"
        Q.reject(err)
      .then () =>
    @append_queue do_append

  append_footer: () =>
    if @footer
      utilities.contents @footer
      .then (contents) =>
        @append contents
    else
      Q.resolve()

  write: (text) ->
    utilities.write @path, text, @file_options
    .catch (err) =>
      utilities.error "Error writing to #{@path}"
      Q.reject(err)


###
# @class Template
###
class Template
  re_template_settings: /^\s*<!\-\-(\{[\s\S]+?\})\-\->/

  node_version = utilities.version_parts(process.version)
  file_options: if node_version[1] < 10 then 'utf8' else {encoding: 'utf8'}

  ###
  # @param path The path to the file from the base source directory.
  ###
  constructor: (out_path, @options) ->
    @out_path = out_path
    @sources = []
    @out_file = @get_out_file()

  get_out_file: =>
    new OutFile @out_path, @options

  add_source: (src_path) ->
    basename = utilities.replace_extension(
      path.basename(src_path)
      @options.extension
      ''
    )
    name = utilities.to_case @options.function_case, basename
    dirname = path.relative @options.source_dir, path.dirname(src_path)
    dirname = path.join @options.source_dir_basename, dirname
    path_parts = dirname.split path.sep
    path_parts_cased = for part in path_parts
      utilities.to_case @options.path_case, part
    @sources.push {
      path: src_path,
      basename: basename,
      name: name,
      dirnane: dirname,
      path_parts: path_parts,
      path_parts_cased: path_parts_cased
    }


  compile: () ->
    compile_one = (item) =>
      utilities.contents item.path, @file_options
      .then (source) =>
        # Get local file-level settings, if any
        file_settings = source.match(@re_template_settings)
        if file_settings
          file_settings = file_settings[1]
          file_settings = eval("(#{file_settings});")
          # Remove this from the source so we don't get compile errors.
          source = source.replace @re_template_settings, ''
        # Get the full template_settings object
        template_settings = _.extend({}, _.templateSettings,
            @options.template_settings, file_settings)
        # Compile the template function
        template_fn = _.template(source, null, template_settings)
        if @options.template_wrapper
          template_fn_source = @options.template_wrapper + '(' +
            template_fn.source + ')'
        else
          template_fn_source = template_fn.source
        # Get full javascript path to compiled template
        template_path = [@options.namespace].concat(item.path_parts_cased,
            [item.name]).join('.')
        # Write to file
        @out_file.append_template template_path, template_fn_source
        .then (res) =>
          utilities.log "#{item.path} -> #{@out_file.path}"
          Q.resolve(res)
    # now to sequence!
    @sources.map( (item) -> () -> compile_one(item)).reduce(Q.when, Q(null))
    .then () =>
      @out_file.append_footer()
###
# Cleans the out_dir specified by the user. By clean, we mean totally remove.
# The user will be prompted before we remove the compiled directory unless
# they have turned the unsafe_clean option on.
#
# @param argv The arguments object from optimist
# @param cb A callback for when the clean operation is done
###
clean_out_dir = (argv, cb) ->
  p = null;
  if argv.unsave_clean
    p = Q.resolve(true)
  else
    p = utilities.question  "Really remove #{JSON.stringify argv.out_dir} and all its contents? (Y/n) "
  p.then (ans) ->
    if ans
      utilities.log "Removing #{argv.out_dir} prior to compiling..."
      utilities.rmdirr(argv.out_dir, false, cb)
    else
      Q.resolve()

###
# The main entry point from the cli _plate command. Does some basic sanity
# checking, performs the clean if requested and passes the rest on to _compile.
#
# @param argv the optimist argv object.
###
@compile = (argv) ->
  utilities.stat(argv.source_dir)
  .then (stat) ->
    if not stat.isDirectory()
      Q.reject(utilities.not_dir_error argv.source_dir)
    else
      Q.resolve()
  .then () ->
    utilities.stat(argv.out_dir)
  .then (stat) =>
    if stat.isDirectory()
      if argv.clean
        @clean_out_dir argv
      else
        Q.resolve()
    else
      Q.reject(utilities.not_dir_error argv.out_dir)
  .catch (err) ->
    if err.code is 'ENOENT'
      Q.resolve()
    else
      Q.reject(err)
  .then () =>
    @compile_dir argv.source_dir, argv


###
# This function recursively gathers information about the files and directory
# structure so we can properly compile the template files. Ensures we only
# compile files with the proper extension.
#
# @param source_dir The source dir we are compiling from.
# @param options The original argv object from optimist
# @param cb A callback
###
@compile_dir = (source_dir, options) =>
  mappings = {}
  @compile_dir_helper(source_dir, source_dir, options, mappings)
  .then () =>
    compiles = []
    for out, files of mappings
      template = new Template(out, options)
      for f in files
        template.add_source(f)
      compiles.push template.compile()
    #this part can be parallel
    Q.all(compiles)

@compile_dir_helper = (start_dir, cur_dir, options, mappings) ->
  # three modes...
  # 1. file... each file encountered is compiled separately
  # 2. directory... each directory encountered is compiled separately
  # 3. combined... all combined to a single file
  # first step, create source_dir to out file,  path mappings.
  Q.resolve(mappings)
  .then (mappings) =>
    utilities.readdir (cur_dir)
    .then (contents) =>
      Q.all contents.map (item) =>
        # for each item in the directory
        itempath = path.join cur_dir, item
        utilities.stat itempath
        .then (stat) -> {stat:stat, path: itempath}
    .then (stats) =>
      dirs = stats.filter (x) -> x.stat.isDirectory()
      files = stats.filter (x) ->
        not x.stat.isDirectory() and path.extname(x.path) is options.extension
      @update_mappings start_dir, cur_dir, dirs, files, options, mappings

@to_out_file = (start_dir, cur_dir, options) ->
  dirname = path.relative start_dir, cur_dir
  if dirname == ''
    # todo, make this a reasonable default
    dirname = 'templates'
  ext = (if options.keep_extension then options.extension else '') + '.js'
  fpath = utilities.replace_extension dirname, options.extension, ext
  path.join(options.out_dir, fpath)

@update_mappings= (start_dir, cur_dir, dirs, files, options, mappings) ->
  result = Q.resolve()
  switch options['compile-style']
    when 'directory'
      out_path = @to_out_file start_dir, cur_dir, options
      mappings[out_path] = files.map (x) -> x.path
      dirfns = dirs.map (dir) =>
        () =>
          @compile_dir_helper start_dir, dir.path, options, mappings
      result = dirfns.reduce(Q.when, Q.resolve())
      result.then () ->
        Q.resolve(mappings)
    else
      result =  Q.reject(new Error('unimplemented'))
  result

# vim: et sw=2 sts=2
