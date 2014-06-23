
## Initialization

    debug   = (require 'debug') 'frugal-couch.tests.helpers'
    nock    = require 'nock'
    expect  = (require 'chai').expect
    _       = require 'lodash'
    path    = require 'path'
    fs      = require 'fs'
    config  = require './fixtures/config.json'
    nano    = (require 'nano') config.couch
    async   = require 'async'

## Private functions

    pathToTestJson = (filename) ->
        return path.join __dirname, '.', filename

    nockActionIsRecording = (nocksOrFilename) ->
        return false unless _.isString nocksOrFilename
        return false if _.isUndefined process.env.NOCK_RECORDING
        return true if process.env.NOCK_RECORDING == '1'

        enabledFilenames = process.env.NOCK_RECORDING.split(';')
        return _.some enabledFilenames, (enabledFilename) -> enabledFilename == nocksOrFilename

    recordNocks = (options) ->
        clonedOptions = _.clone options or {}
        clonedOptions.dont_print = true
        clonedOptions.output_objects = true
        nock.recorder.rec clonedOptions

    loadNockDefs = (filename) ->
        defs = nock.loadDefs pathToTestJson filename
        expect(defs).to.exist
        defs

    defineNocks = (nockDefs) ->
        expect(nockDefs).to.exist
        nock.define nockDefs

    nocksDone = (nocks) ->
        _.each nocks, (nock) ->
            nock.done()

    dumpRecordedNocks = (filename) ->
        nock.restore()
        # Format output JSON for easier reading
        recordedNocksJson = (JSON.stringify nock.recorder.play()).replace /{"scope"/g, '\n\r{"scope"'
        if not filename
            console.log recordedNocksJson
        else
            fs.writeFileSync pathToTestJson(filename), recordedNocksJson
        nock.recorder.clear()

## Public functions

If we are recording (NOCL_RECORDING == '1') then we start the recording and return the filename to which we will be saving them. Otherwise, we load the nock definitions from the file and give the user a chance to post-process them.

    startNocking = (filename, options) ->

        if nockActionIsRecording filename
            debug 'recording nock requests to', filename
            nock.restore()
            nock.recorder.clear()
            recordNocks(options?.recorderOptions)
            return filename
        else
            debug 'reading nock requests from', filename

            defs = loadNockDefs filename
            if options and options.preprocessor
                options.preprocessor defs

            nocks = defineNocks defs

            if options and options.postprocessor
                options.postprocessor nocks

            debug 'tracking', nocks.length, 'nock requests'

            nock.activate() if not nock.isActive()

            return nocks

    exports.startNocking = startNocking

    stopNocking = (nocksOrFilename) ->
        if nockActionIsRecording nocksOrFilename
            debug 'stopped recording nock requests'
            dumpRecordedNocks nocksOrFilename
        else
            debug 'stopped tracking nock requests'
            nocksDone nocksOrFilename

    exports.stopNocking = stopNocking

    exports.database = nano.use('frugal-couch-tests')

    createDatabase = (callback) ->

        nano.db.destroy 'frugal-couch-tests', (err) ->
            expect(err).to.not.exist
            nano.db.create 'frugal-couch-tests', callback

    exports.createDatabase = createDatabase