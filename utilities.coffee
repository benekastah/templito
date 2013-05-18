
events = require 'events'
child_process = require 'child_process'
readline = require 'readline'


logger = (logfn) ->
  (args...) ->
    console[logfn] "#{new Date()}  ", args...

@log = logger 'log'
@error = logger 'error'
@warn = logger 'warn'

###
# with_prompter creates a readline prompter on demand. Since the program won't
# exit until each prompter is closed, it requires the prompter to be used in a
# sort of "session".
#
# @param fn callback which takes two parameters:
#   @param prompter the readline interface
#   @param close the cleanup callback.
###
@with_prompter = (fn) ->
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
@mkdirp = (dir, cb) ->
  child_process.exec "mkdir -p #{JSON.stringify dir}", cb


###
# Recursively removes directories.
#
# @param dir the directory
# @param force whether rm -rf should be used
# @param cb a callback (called by child_process.exec)
###
@rmdirr = (dir, force, cb) ->
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
do =>
  ee = new events.EventEmitter()
  groups = {}

  event_cb = (event_name) ->
    group = groups[event_name] ?= {data: [], length: 0, updated: 0}
    idx = group.length
    group.length += 1
    ->
      group.data[idx] = arguments
      group.updated += 1
      if group.updated is group.length
        group[event_name] = null
        ee.emit event_name, group.data...

  @group_cb = (cb) ->
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
# @param fpath path to the thing that isn't a directory
# @returns Error ENOTDIR Error
###
@not_dir_error = (fpath) ->
  err = new Error("Not a directory: #{JSON.stringify fpath}")
  err.path = fpath
  err.code = 'ENOTDIR'
  err


re_trailing_path = /\/?$/
###
# Converts a string-like-this/ into a string-like-this.
#
# @param fpath the string to convert
# @returns String the trimmed string
###
trim_trailing_path = (fpath) ->
  return fpath.replace re_trailing_path, ''


re_to_capital_case = /(^|[\-_\s])([a-z])/g
###
# Converts a name-like-this, a name_like_this or a nameLikeThis into a
# NameLikeThis.
#
# @param name the thing you want to convert
# @returns String the capital-cased name
###
to_capital_case = (name) ->
  result = name.replace re_to_capital_case, (a, b, match) -> match.toUpperCase()
  trim_trailing_path result


###
# Converts a name-like-this, a name_like_this or a NameLikeThis into a
# nameLikeThis.
#
# @param name the thing you want to convert
# @returns String the camel-cased name
###
to_camel_case = (name) ->
  # to_capital_case calls trim_trailing_path for us.
  result = to_capital_case name
  result = result.charAt(0).toLowerCase() + result.substr(1)


re_to_snake_case = /([a-z])([A-Z])/g
re_acronym_to_snake_case = /([A-Z]+)([A-Z])/g
re_dash = /\-/g
###
# Converts a name-like-this or a nameLikeThis or a NameLikeThis into a
# name_like_this.
#
# @param name the thing you want to convert
# @returns String the snake-cased name
###
to_snake_case = (name) ->
  replacer = '$1_$2'
  result = name.replace re_to_snake_case, replacer
  result = result.replace re_acronym_to_snake_case, replacer
  result = result.replace re_dash, '_'
  trim_trailing_path result.toLowerCase()


###
# Converts a name to the specified case.
#
# @param case the case you want to convert the name to
# @param name the name you want to convert
# @returns String the converted string
###
@to_case = (case_type, name) ->
  switch case_type
    when 'CapitalCase' then to_capital_case name
    when 'camelCase' then to_camel_case name
    when 'snake_case' then to_snake_case name
    else throw "Unknown case type: #{case_type}"


###
# Replaces the specified file-extension with a new one
#
# @param name The string to process
# @param ext The extension to remove from the string
# @param new_ext The new extension to add in place of ext
# @returns String the new string
###
@replace_extension = (name, ext, new_ext) ->
  re_ext = new RegExp "(\\#{ext})?$", 'gi'
  name.replace re_ext, new_ext
