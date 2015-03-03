_ = require 'underscore-plus'

Tag = require './tag'
Model = require './model'
Contact = require './contact'
Actions = require '../actions'
Attributes = require '../attributes'

module.exports =
class Thread extends Model

  @attributes: _.extend {}, Model.attributes,

    'snippet': Attributes.String
      modelKey: 'snippet'

    'subject': Attributes.String
      modelKey: 'subject'

    'unread': Attributes.Boolean
      queryable: true
      modelKey: 'unread'

    'version': Attributes.Number
      modelKey: 'version'

    'tags': Attributes.Collection
      queryable: true
      modelKey: 'tags'
      itemClass: Tag

    'participants': Attributes.Collection
      modelKey: 'participants'
      itemClass: Contact

    'lastMessageTimestamp': Attributes.DateTime
      queryable: true
      modelKey: 'lastMessageTimestamp'
      jsonKey: 'last_message_timestamp'

  @naturalSortOrder: ->
    Thread.attributes.lastMessageTimestamp.descending()

  fromJSON: (json) =>
    super(json)
    @unread = @isUnread()
    @

  tagIds: =>
    _.map @tags, (tag) -> tag.id

  isUnread: ->
    @tagIds().indexOf('unread') != -1

  isStarred: ->
    @tagIds().indexOf('starred') != -1

  markAsRead: ->
    MarkThreadReadTask = require '../tasks/mark-thread-read'
    task = new MarkThreadReadTask(@id)
    Actions.queueTask(task)

  star: ->
    @addRemoveTags(['starred'], [])

  unstar: ->
    @addRemoveTags([], ['starred'])

  toggleStar: ->
    if @isStarred()
      @unstar()
    else
      @star()

  archive: ->
    Actions.postNotification({message: "Archived thread", type: 'success'})
    @addRemoveTags(['archive'], ['inbox'])

  unarchive: ->
    @addRemoveTags(['inbox'], ['archive'])

  addRemoveTags: (tagIdsToAdd, tagIdsToRemove) ->
    # start web change, which will dispatch more actions
    AddRemoveTagsTask = require '../tasks/add-remove-tags'
    task = new AddRemoveTagsTask(@id, tagIdsToAdd, tagIdsToRemove)
    Actions.queueTask(task)