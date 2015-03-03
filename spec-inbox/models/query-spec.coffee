ModelQuery = require '../../src/flux/models/query'
{Matcher} = require '../../src/flux/attributes'
Thread = require '../../src/flux/models/thread'
Namespace = require '../../src/flux/models/namespace'

describe "ModelQuery", ->
  beforeEach ->
    @db = {}

  describe "where", ->
    beforeEach ->
      @q = new ModelQuery(Thread, @db)
      @m1 = Thread.attributes.id.equal(4)
      @m2 = Thread.attributes.tags.contains('inbox')

    it "should accept an array of Matcher objects", ->
      @q.where([@m1,@m2])
      expect(@q._matchers.length).toBe(2)
      expect(@q._matchers[0]).toBe(@m1)
      expect(@q._matchers[1]).toBe(@m2)

    it "should accept a single Matcher object", ->
      @q.where(@m1)
      expect(@q._matchers.length).toBe(1)
      expect(@q._matchers[0]).toBe(@m1)

    it "should append to any existing where clauses", ->
      @q.where(@m1)
      @q.where(@m2)
      expect(@q._matchers.length).toBe(2)
      expect(@q._matchers[0]).toBe(@m1)
      expect(@q._matchers[1]).toBe(@m2)

    it "should accept a shorthand format", ->
      @q.where({id: 4, lastMessageTimestamp: 1234})
      expect(@q._matchers.length).toBe(2)
      expect(@q._matchers[0].attr.modelKey).toBe('id')
      expect(@q._matchers[0].comparator).toBe('=')
      expect(@q._matchers[0].val).toBe(4)

    it "should return the query so it can be chained", ->
      expect(@q.where({id: 4})).toBe(@q)

    it "should immediately raise an exception if an un-queryable attribute is specified", ->
      expect(-> @q.where({snippet: 'My Snippet'})).toThrow()

    it "should immediately raise an exception if a non-existent attribute is specified", ->
      expect(-> @q.where({looksLikeADuck: 'of course'})).toThrow()

  describe "order", ->
    beforeEach ->
      @q = new ModelQuery(Thread, @db)
      @o1 = Thread.attributes.lastMessageTimestamp.descending()
      @o2 = Thread.attributes.subject.descending()

    it "should accept an array of SortOrders", ->
      @q.order([@o1,@o2])
      expect(@q._orders.length).toBe(2)

    it "should accept a single SortOrder object", ->
      @q.order(@o2)
      expect(@q._orders.length).toBe(1)

    it "should extend any existing ordering", ->
      @q.order(@o1)
      @q.order(@o2)
      expect(@q._orders.length).toBe(2)
      expect(@q._orders[0]).toBe(@o1)
      expect(@q._orders[1]).toBe(@o2)

    it "should return the query so it can be chained", ->
      expect(@q.order(@o2)).toBe(@q)

  describe "sql", ->
    beforeEach ->
      @runScenario = (klass, scenario) ->
        q = new ModelQuery(klass, @db)
        Matcher.muid = 1
        scenario.builder(q)
        expect(q.sql().trim()).toBe(scenario.sql.trim())

    it "should correctly generate queries with multiple where clauses", ->
      @runScenario Namespace,
        builder: (q) -> q.where({emailAddress: 'ben@inboxapp.com'}).where({id: 2})
        sql: "SELECT `Namespace`.`data` FROM `Namespace`  \
              WHERE `email_address` = 'ben@inboxapp.com' AND `id` = 2"

    it "should correctly generate COUNT queries", ->
      @runScenario Thread,
        builder: (q) -> q.where({namespaceId: 'abcd'}).count()
        sql: "SELECT COUNT(*) as count FROM `Thread`  \
              WHERE `namespace_id` = 'abcd'  "

    it "should correctly generate LIMIT 1 queries for single items", ->
      @runScenario Thread,
        builder: (q) -> q.where({namespaceId: 'abcd'}).one()
        sql: "SELECT `Thread`.`data` FROM `Thread`  \
              WHERE `namespace_id` = 'abcd'  \
              ORDER BY `Thread`.`last_message_timestamp` DESC LIMIT 1"

    it "should correctly generate `contains` queries using JOINS", ->
      @runScenario Thread,
        builder: (q) -> q.where(Thread.attributes.tags.contains('inbox')).where({id: '1234'})
        sql: "SELECT `Thread`.`data` FROM `Thread` \
              INNER JOIN `Thread-Tag` AS `M1` ON `M1`.`id` = `Thread`.`id` \
              WHERE `M1`.`value` = 'inbox' AND `id` = '1234'  \
              ORDER BY `Thread`.`last_message_timestamp` DESC"

      @runScenario Thread,
        builder: (q) -> q.where([Thread.attributes.tags.contains('inbox'), Thread.attributes.tags.contains('unread')])
        sql: "SELECT `Thread`.`data` FROM `Thread` \
              INNER JOIN `Thread-Tag` AS `M1` ON `M1`.`id` = `Thread`.`id` \
              INNER JOIN `Thread-Tag` AS `M2` ON `M2`.`id` = `Thread`.`id` \
              WHERE `M1`.`value` = 'inbox' AND `M2`.`value` = 'unread'  \
              ORDER BY `Thread`.`last_message_timestamp` DESC"

    it "should correctly generate queries with the class's naturalSortOrder when one is available and no other orders are provided", ->
      @runScenario Thread,
        builder: (q) -> q.where({namespaceId: 'abcd'})
        sql: "SELECT `Thread`.`data` FROM `Thread`  \
              WHERE `namespace_id` = 'abcd'  \
              ORDER BY `Thread`.`last_message_timestamp` DESC"

      @runScenario Thread,
        builder: (q) -> q.where({namespaceId: 'abcd'}).order(Thread.attributes.lastMessageTimestamp.ascending())
        sql: "SELECT `Thread`.`data` FROM `Thread`  \
              WHERE `namespace_id` = 'abcd'  \
              ORDER BY `Thread`.`last_message_timestamp` ASC"

      @runScenario Namespace,
        builder: (q) -> q.where({id: 'abcd'})
        sql: "SELECT `Namespace`.`data` FROM `Namespace`  \
              WHERE `id` = 'abcd'  "
