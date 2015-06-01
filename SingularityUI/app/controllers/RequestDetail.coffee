Controller = require './Controller'

Request                = require '../models/Request'
RequestDeployStatus    = require '../models/RequestDeployStatus'

Tasks                  = require '../collections/Tasks'
RequestTasksLogs       = require '../collections/RequestTasksLogs'
RequestTasks           = require '../collections/RequestTasks'
RequestHistoricalTasks = require '../collections/RequestHistoricalTasks'
RequestDeployHistory   = require '../collections/RequestDeployHistory'
RequestHistory         = require '../collections/RequestHistory'

RequestDetailView      = require '../views/request'
PaginatedTableServersideView = require '../views/paginatedTableServersideView'
PaginatedTableClientsideView = require '../views/paginatedTableClientsideView'
ExpandableTableSubview = require '../views/expandableTableSubview'

SimpleSubview          = require '../views/simpleSubview'

class RequestDetailController extends Controller

    templates:
        header:             require '../templates/requestDetail/requestHeader'
        requestHistoryMsg:  require '../templates/requestDetail/requestHistoryMsg'
        stats:              require '../templates/requestDetail/requestStats'
        activeTasks:        require '../templates/requestDetail/requestActiveTasks'
        logs:               require '../templates/taskDetail/taskS3Logs'
        scheduledTasks:     require '../templates/requestDetail/requestScheduledTasks'
        taskHistory:        require '../templates/requestDetail/requestHistoricalTasks'
        deployHistory:      require '../templates/requestDetail/requestDeployHistory'
        requestHistory:     require '../templates/requestDetail/requestHistory'

    initialize: ({@requestId}) ->
        #
        # Data stuff
        #
        @models.request = new Request id: @requestId

        @models.activeDeployStats = new RequestDeployStatus
            requestId: @requestId
            deployId:  undefined

        @collections.activeTasks = new RequestTasks [],
            requestId: @requestId
            state:    'active'

        @collections.scheduledTasks = new Tasks [],
            requestId: @requestId
            state:     'scheduled'

        @collections.requestTasksLogs = new RequestTasksLogs [], {@requestId}

        @collections.requestHistory  = new RequestHistory         [], {@requestId}
        @collections.taskHistory     = new RequestHistoricalTasks [], {@requestId}
        @collections.deployHistory   = new RequestDeployHistory   [], {@requestId}

        #
        # Subviews
        #
        @subviews.header = new SimpleSubview
            model:      @models.request
            template:   @templates.header

        # would have used header subview for this info,
        # but header expects a request model that
        # no longer exists if a request is deleted
        @subviews.requestHistoryMsg = new SimpleSubview
            collection: @collections.requestHistory
            template:   @templates.requestHistoryMsg

        @subviews.stats = new SimpleSubview
            model:      @models.activeDeployStats
            template:   @templates.stats

        @subviews.activeTasks = new SimpleSubview
            collection: @collections.activeTasks
            template:   @templates.activeTasks
            extraRenderData: ->
                { taskLogPath: config.runningTaskLogPath }

        @subviews.requestTasksLogs = new PaginatedTableClientsideView
            collection: @collections.requestTasksLogs
            template:   @templates.logs

        @subviews.scheduledTasks = new SimpleSubview
            collection:      @collections.scheduledTasks
            template:        @templates.scheduledTasks
            extraRenderData: (subView) =>
                { request: @models.request.toJSON() }

        @subviews.taskHistory = new PaginatedTableServersideView
            collection: @collections.taskHistory
            template:   @templates.taskHistory
            extraRenderData: ->
                { taskLogPath: config.finishedTaskLogPath }

        @subviews.deployHistory = new PaginatedTableServersideView
            collection: @collections.deployHistory
            template:   @templates.deployHistory

        @subviews.requestHistory = new PaginatedTableServersideView
            collection: @collections.requestHistory
            template:   @templates.requestHistory

        #
        # The stats stuff depends on info we get from @models.request
        #
        @models.request.on 'sync', =>
            activeDeploy = @models.request.get 'activeDeploy'
            if activeDeploy?.id? and not @models.activeDeployStats.deployId
                @models.activeDeployStats.deployId = activeDeploy.id
                @models.activeDeployStats.fetch()

        #
        # Main view & stuff
        #
        @setView new RequestDetailView _.extend {@requestId, @subviews},
            model: @models.request
            history: @collections.taskHistory
            activeTasks: @collections.activeTasks

        @refresh()

        app.showView @view

    refresh: ->
        @models.request.fetch().error =>
            # ignore 404 so we can still display info about
            # deleted requests (show in `requestHistoryMsg`)
            @ignore404
            app.caughtError()

        if @models.activeDeployStats.deployId?
            @models.activeDeployStats.fetch().error @ignore404

        @collections.activeTasks.fetch().error    @ignore404
        @collections.scheduledTasks.fetch().error @ignore404
        
        if @collections.requestHistory.currentPage is 1
            @collections.requestHistory.fetch()
                .done =>
                    # Request never existed
                    if @collections.requestHistory.length is 0
                        app.router.notFound()
                .error =>
                    @ignore404

        if @collections.taskHistory.currentPage is 1
            @collections.taskHistory.fetch().error    @ignore404
        if @collections.deployHistory.currentPage is 1
            @collections.deployHistory.fetch().error  @ignore404

        if @collections.requestTasksLogs
            @collections.requestTasksLogs.fetch().error =>
                # It probably means S3 logs haven't been configured
                app.caughtError()
                delete @collections.s3Logs

module.exports = RequestDetailController
