
fs = require 'fs'
path = require 'path'
child_process = require 'child_process'
events = require 'events'
readline = require 'readline'
try
  _ = require 'underscore'
catch e
  console.warn 'Underscore could not be loaded. Precompiling templates will '+
               'not work until this problem is resolved.', e

# Utility functions

###
# with_prompter creates a readline prompter on demand. Since the program won't
# exit until each prompter is closed, it requires the prompter to be used in a
# sort of "session".
#
# @param fn callback which takes two parameters:
#   @param prompter the readline interface
#   @param close the cleanup callback.
###
with_prompter = (fn) ->
  prompter = readline.createInterface
    input: process.stdin
    output: process.stdout
  fn prompter, ->
    prompter.close()


###
# mkdir -p
#
# @param dir the directory to make
# @param cb the callback (called by child_process.exec)
###
mkdirp = (dir, cb) ->
  child_process.exec "mkdir -p #{JSON.stringify dir}", cb


###
# Recursively removes directories.
#
# @param dir the directory
# @param force whether rm -rf should be used
# @param cb a callback (called by child_process.exec)
###
rmdirr = (dir, force, cb) ->
  _dir = JSON.stringify dir
  _f = if force then 'f' else ''
  cmd = "if [ -d #{_dir} ]; then rm -r#{_f} #{_dir}; fi"
  child_process.exec cmd, cb


###
# group_cb is a quick 'n dirty async flow manager.
#
# @param cb a callback that will be called when the group is finished.
#
# @returns Function when called, this function creates a new callback for the
# group. As soon as every callback in the group is called, the group is closed.
# If this function is called again, it will recreate the internal callback
# group and will continue to work properly.
###
group_cb = null
do ->
  ee = new events.EventEmitter()
  groups = {}

  event_cb = (event_name) ->
    group = groups[event_name] ?= {data: [], length: 0, updated: 0}
    idx = group.length
    group.length += 1
    ->
      group.data[idx] = arguments
      group.updated += 1
      #console.log group
      if group.updated is group.length
        group[event_name] = null
        ee.emit event_name, group.data...

  group_cb = (cb) ->
    event_name = '' + Math.random()
    if cb
      ee.on(event_name, cb)
    ret = ->
      ret.count += 1
      event_cb(event_name)
    ret.count = 0
    ret


###
# Create a fake ENOTDIR Error a la nodejs.
#
# @param path path to the thing that isn't a directory
# @returns Error ENOTDIR Error
###
notDirError = (path) ->
  err = new Error("Not a directory: #{JSON.stringify path}")
  err.path = path
  err.code = 'ENOTDIR'
  err


re_trailing_path = /\/?$/
re_to_capital_case = /(^|[\-_\s])([a-z])/g


###
# Converts a name to capital case from a_name_like_this or a-name-like-this.
#
# @param name the thing you want to convert
# @returns String the capital cased name
###
to_capital_case = (name) ->
  result = name.replace re_to_capital_case, (a, b, match) -> match.toUpperCase()
  result.replace re_trailing_path, ''


###
# Constructs a javascript object path. Used for taking path segments and
# converting them to javascript namespaces.
#
# @param namespace the front of the object path
# @param basename the next part of the object path
# @returns a new object path
###
get_object_path = (namespace, basename) ->
  "#{namespace}.#{to_capital_case basename}"


###
# Takes a number of object paths and sets all the intermediate default values
# so that each object in the path exists. Ensures that if two object paths are
# the same, they will not be initialized more than once in the same call.
#
# @param object_paths... n number of object paths
# @returns String javascript code to initialize the paths
###
default_object_paths = (object_paths...) ->
  defaults = []
  for object_path in object_paths
    parts = object_path.split '.'
    _parts = [parts[0]]
    parts = parts.slice 1

    for part in parts
      _parts.push part
      part = _parts.join '.'
      _default = "#{part} || (#{part} = {});"
      if _default not in defaults
        defaults.push _default

  defaults.join '\n'


###
# Cleans the out_dir specified by the user. By clean, we mean totally remove.
# The user will be prompted before we remove the compiled directory unless
# they have turned the unsafe_clean option on.
#
# @param argv The arguments object from optimist
# @param cb A callback for when the clean operation is done
###
clean_out_dir = (argv, cb) ->
  with_prompter (prompter, close) ->
    clean = (yn) ->
      close()
      if yn in [true, 'y', 'Y']
        console.log "Cleaning out previously compiled files, if any."
        rmdirr(argv.out_dir, false, cb)
    if argv.unsafe_clean
      clean true
    else
      prompter.question(
        "Really remove #{JSON.stringify argv.out_dir} and all its contents? (Y/n) ",
        clean
      )


###
# The main entry point from the cli _plate command. Does some basic sanity
# checking, performs the clean if requested and passes the rest on to _compile.
#
# @param argv the optimist argv object.
###
@compile = (argv) ->
  {source_dir, out_dir, compile_style, extension, namespace} = argv

  if _ and argv.template_settings
    try
      _.templateSettings = _.extend(
        eval("(#{argv.template_settings})")
        _.templateSettings
      )
    catch e
      console.warn '--template-settings not a valid javascript object'
      console.error e

  stats_cb = group_cb ([err1], [err2]) ->
    throw err if (err = err1 or err2)
    argv.re_extension = new RegExp("\\.#{extension}$", 'i')
    _compile argv.source_dir, argv.out_dir, argv.namespace, argv

  cb1 = stats_cb()
  srcstat = fs.stat source_dir, (err, stat) ->
    throw err if err
    if not stat.isDirectory()
      cb1(notDirError source_dir)
    else
      cb1()

  out_cb = stats_cb()
  out_dirstat = fs.stat out_dir, (err, stat) ->
    if err and err.code isnt 'ENOENT'
      throw err
    else if !stat
      out_cb()
    else if stat.isDirectory()
      if argv.clean
        clean_out_dir argv, out_cb
      else
        out_cb()
    else
      out_cb(notDirError out_dir)


###
# This function recursively gathers information about the files and directory
# structure so we can properly compile the template files. Ensures we only
# compile files with the proper extension.
#
# @param source_dir The source dir we are compiling from.
# @param out_dir The directory we are compiling to.
# @param namespace The base namespace of the javascript object that will hold
# the templates in the part of the directory tree we are looking at.
# @param argv The original argv object from optimist
# @param cb A callback
###
_compile = (source_dir, out_dir, namespace, argv, cb) ->
  results =
    items: []
    out_dir: out_dir
    source_dir: source_dir

  basename = (path.basename source_dir).replace re_trailing_path, ''
  object_path = get_object_path namespace, basename

  item_cb = group_cb ->
    for info in arguments
      [err, branch_info] = info or []
      throw err if err
      if branch_info
        [dir, branch] = branch_info
        results.items.push
          type: 'directory'
          data: branch
          name: dir

    _compile_with_branches results, object_path, argv, cb

  stat_cb = group_cb ->
    if not item_cb.count
      item_cb() null

  fs.readdir source_dir, (err, contents) ->
    throw err if err
    for item in contents then do (item) ->
      scb = stat_cb()
      itempath = path.join source_dir, item
      fs.stat itempath, (err, stat) ->
        throw err if err
        if stat.isDirectory()
          if argv.compile_style isnt 'combined'
            new_out_dir = path.join out_dir, item
          else
            new_out_dir = out_dir
          _compile itempath, new_out_dir, object_path, argv, item_cb()
        else if argv.re_extension.test item
          _cb = item_cb()
          entry = item.replace argv.re_extension, ''
          fs.readFile itempath, 'utf8', (err, data) ->
            results.items.push
              type: 'file'
              data: data
              name: entry
            _cb err
        scb null


warning_message = """
/** WARNING: This file is automatically generated by plate.
 *  Do not edit this file if you plan on using plate to continue to
 *  generate template files. If you run plate on your templates again,
 *  all changes to this file will be lost!
 */
"""
re_file_opts = /^<!\-\-(\{.*?\})\-\->/m
touched_files = {}

###
# Takes the information gathered from _compile and performs the compile
# operation. This function is supposed to respond to the compile_style option
# in argv, but fails to do so properly. Currently the only option that works
# is "directory".
###
_compile_with_branches = (data, object_path, argv, cb) ->
  # Get a copy of the callback that won't take any arguments
  cb = do (cb) ->
    -> cb and cb()

  #console.log data

  if not data.items.length
    cb()
  else
    mkdirp data.out_dir, (err) ->
      throw err if err

      _cb = group_cb cb
      js_head = """
      #{warning_message}

      """

      js_body = null
      object_paths = null
      setup_defaults = ->
        js_body = ""
        object_paths = []
      setup_defaults()

      write = ->
        out = path.join data.out_dir, "#{path.basename data.source_dir}.js"
        out = path.normalize out
        console.log "writing #{JSON.stringify out} to file..."
        js_head += default_object_paths object_paths...
        js = js_head + '\n\n' + js_body

        # Determine if we need to append to this file or not
        if touched_files[out]
          write_fn = fs.appendFile
        else
          write_fn = fs.writeFile
          touched_files[out] = yes
        # write the file
        write_fn out, js, {encoding: 'utf8'}, _cb()

        setup_defaults()

      if argv.template_settings
        underscore_opts = _.templateSettings
      else
        underscore_opts = null

      for name, info of data.items then do (name, info) ->
        if info.type is 'file'
          object_paths.push object_path

          file_opts = (info.data.match(re_file_opts) or [])[1]
          if file_opts
            info.data = info.data.replace re_file_opts, ''
            file_opts = eval "(#{file_opts})"
          else
            file_opts = null

          # Precompile with underscore and include the source in the file
          # rather than doing it at runtime.
          if _ and not argv.no_precompile
            template_fn = (_.template info.data, null, file_opts).source
            console.log file_opts
          else
            # TODO The no_precompile path is broken because it tries to json
            # encode the underscore options object, but RegExp objects won't
            # json encode.
            if underscore_opts
              if file_opts
                for key, val of underscore_opts
                  file_opts[key] ?= val
              else
                file_opts = underscore_opts

            template_fn = """
            _.template(
                #{JSON.stringify info.data},
                null, #{JSON.stringify file_opts})
            """

          js_body += """
          #{object_path}.#{info.name} = #{template_fn};


          """
          if argv.compile_style is 'file'
            write()

      if argv.compile_style isnt 'file'
        write()
