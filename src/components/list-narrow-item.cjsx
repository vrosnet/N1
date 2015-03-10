_ = require 'underscore-plus'
React = require 'react/addons'
{ComponentRegistry} = require 'inbox-exports'

ThreadListItemMixin = require './thread-list-item-mixin.cjsx'

DefaultParticipants = React.createClass
  render: ->
    <div className="participants">
      {_.pluck(@props.participants, "email").join ", "}
    </div>

module.exports =
ThreadListNarrowItem = React.createClass
  mixins: [ComponentRegistry.Mixin, ThreadListItemMixin]
  displayName: 'ThreadListNarrowItem'
  components: ["Participants"]

  render: ->
    Participants = @state.Participants ? DefaultParticipants
    <div className={@_containerClasses()} onClick={@_onClick} id={@props.thread.id}>
      <div className="thread-title">
        <span className="btn-icon star-button pull-right"
          onClick={@_toggleStar}
        ><i className={"fa " + (@_isStarred() and 'fa-star' or 'fa-star-o')}/></span>
        <div className="message-time">
          {@threadTime()}
        </div>
        <Participants participants={@props.thread.participants} context={'list'} clickable={false}/>
      </div>
      <div className="preview-body">
        <span className="subject">{@_subject()}</span>
        <span className="snippet">{@_snippet()}</span>
      </div>
    </div>

  _containerClasses: ->
    React.addons.classSet
      'unread': @props.unread
      'selected': @props.selected
      'thread-list-item': true
      'thread-list-narrow-item': true