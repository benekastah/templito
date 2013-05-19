"use strict"

typeof global is 'undefined' and (window.global = window)

global.Templito =
  View: {}

_.templateSettings =
  evaluate: /<%([\s\S]+?)%>/g
  interpolate: /<%=!([\s\S]+?)%>/g
  escape: /<%=(?!!)([\s\S]+?)%>/g

$(document).ready ->
  $(document.body).html (new Templito.View.HomeView).el
