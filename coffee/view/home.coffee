"use strict"

Templito.View.HomeView = Backbone.View.extend
  tagName: 'div'

  initialize: ->
    @$el = $(@el)
    @render()

  render: ->
    @$el.html Templito.Template.layout
      nav: [{
        name: 'Home'
        href: '/'
      }, {
        name: 'Github',
        href: 'https://github.com/benekastah/templito'
      }]
