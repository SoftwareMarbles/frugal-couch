
## Initialization

    debug = (require 'debug') 'frugal-couch.tests'
    frugal = require '../frugal'
    expect = (require 'chai').expect
    _ = require 'lodash'
    helpers = require './helpers'

## `overwriteBulk`

    describe 'frugal-couch module', ->

        before (done) ->
            nocks = helpers.startNocking '/fixtures/before.json'
            helpers.createDatabase (err) ->
                helpers.stopNocking nocks
                expect(err).to.not.exist
                done()

        describe 'has overwriteBulk function', ->

            it 'expects valid input parameters', (done) ->
                expect(frugal.overwriteBulk).to.throw 'Callback parameter required'

                frugal.overwriteBulk undefined, undefined, (err) ->
                    expect(err).to.exist
                    expect(err.message).to.equal 'Bad input parameters'

                    mockNano = {}
                    frugal.overwriteBulk mockNano, undefined, (err) ->
                        expect(err).to.exist
                        expect(err.message).to.equal 'Bad input parameters'

                        frugal.overwriteBulk mockNano, {}, (err) ->
                            expect(err).to.exist
                            expect(err.message).to.equal 'Bad input parameters'

                            frugal.overwriteBulk mockNano, [], (err, result) ->
                                expect(err).to.not.exist
                                expect(result).to.exist
                                expect(result).to.deep.equal { inserted: [], updated: [], resurected: [], revs: {}, errors: {} }
                                done()

            it 'bulk uploads previously inexisting docs', (done) ->
                nocks = helpers.startNocking '/fixtures/overwriteBulk.1.json'

                frugal.overwriteBulk helpers.database, [{ _id: '1', test: 'A test doc'}], (err, result) ->
                    helpers.stopNocking nocks
                    expect(err).to.not.exist
                    expect(result).to.exist
                    expect(result.inserted.length).to.equal 1
                    expect(result.updated.length).to.equal 0
                    expect(result.resurected.length).to.equal 0
                    expect(result.revs).to.not.be.empty
                    expect(result.errors).to.be.empty
                    done()

            it 'bulk uploads previously inexisting docs and then updates it', (done) ->
                nocks = helpers.startNocking '/fixtures/overwriteBulk.2.json'

                frugal.overwriteBulk helpers.database, [{ _id: '2', test: 'A test doc'}], (err, result) ->
                    expect(err).to.not.exist
                    expect(result).to.exist
                    expect(result.inserted.length).to.equal 1
                    expect(result.updated.length).to.equal 0
                    expect(result.resurected.length).to.equal 0
                    expect(result.revs).to.not.be.empty
                    expect(result.errors).to.be.empty
                    frugal.overwriteBulk helpers.database, [{ _id: '2', test: 'An updated test doc'}], (err, result) ->
                        helpers.stopNocking nocks
                        expect(err).to.not.exist
                        expect(result).to.exist
                        expect(result.inserted.length).to.equal 0
                        expect(result.updated.length).to.equal 1
                        expect(result.resurected.length).to.equal 0
                        expect(result.revs).to.not.be.empty
                        expect(result.errors).to.be.empty
                        done()

            it 'bulk uploads previously inexisting docs and resurects it after a delete', (done) ->
                nocks = helpers.startNocking '/fixtures/overwriteBulk.3.json'

                frugal.overwriteBulk helpers.database, [{ _id: '3', test: 'A test doc'}], (err, result) ->
                    expect(err).to.not.exist
                    expect(result).to.exist
                    expect(result.inserted.length).to.equal 1
                    expect(result.updated.length).to.equal 0
                    expect(result.resurected.length).to.equal 0
                    expect(result.revs).to.not.be.empty
                    expect(result.errors).to.be.empty

                    helpers.database.destroy '3', result.revs['3'], (err, body) ->
                        expect(err).to.not.exist
                        expect(body).to.exist

                        frugal.overwriteBulk helpers.database, [{ _id: '3', test: 'A resurected test doc'}], (err, result) ->
                            helpers.stopNocking nocks
                            expect(err).to.not.exist
                            expect(result).to.exist
                            expect(result.inserted.length).to.equal 0
                            expect(result.revs).to.not.be.empty
                            expect(result.errors).to.be.empty
                            done()

        describe 'has partialUpdateBulk function', ->

            it 'expects valid input parameters', (done) ->
                expect(frugal.partialUpdateBulk).to.throw 'Callback parameter required'

                frugal.partialUpdateBulk undefined, undefined, undefined, (err) ->
                    expect(err).to.exist
                    expect(err.message).to.equal 'Bad input parameters'

                    mockNano = {}
                    frugal.partialUpdateBulk mockNano, undefined, undefined, (err) ->
                        expect(err).to.exist
                        expect(err.message).to.equal 'Bad input parameters'

                        frugal.partialUpdateBulk mockNano, {}, undefined, (err) ->
                            expect(err).to.exist
                            expect(err.message).to.equal 'Bad input parameters'

                            frugal.partialUpdateBulk mockNano, [], [], (err) ->
                                expect(err).to.exist
                                expect(err.message).to.equal 'Bad input parameters'

                                frugal.partialUpdateBulk mockNano, [], _.noop, (err, result) ->
                                    expect(err).to.not.exist
                                    expect(result).to.exist
                                    expect(result).to.deep.equal { revs: {}, errors: {} }
                                    done()

            it 'bulk updates docs', (done) ->
                nocks = helpers.startNocking '/fixtures/partialUpdateBulk.1.json'

                docs = [
                    { _id: '4.1', test: 'A test doc' },
                    { _id: '4.2', test: 'A test doc' },
                    { _id: '4.3', test: 'A test doc' },
                    { _id: '4.4', test: 'A test doc' }
                ]
                docIdsToUpdate = ['4.1', '4.3']

                frugal.overwriteBulk helpers.database, docs, (err, result) ->
                    expect(err).to.not.exist
                    expect(result).to.exist
                    expect(_.keys(result.revs).length).to.equal docs.length

                    frugal.partialUpdateBulk helpers.database, docIdsToUpdate, (doc) ->
                        doc.test = doc.test + doc._id
                    , (err, result) ->
                        helpers.stopNocking nocks
                        expect(err).to.not.exist
                        expect(result).to.exist
                        expect(_.keys(result.revs).length).to.equal docIdsToUpdate.length
                        _.each docIdsToUpdate, (docId) ->
                            expect(result.revs[docId].indexOf('2-')).equal 0
                        expect(result.errors).to.be.empty
                        done()

        describe 'has iterateViewBulk function', ->

            it 'expects valid input parameters', (done) ->
                expect(frugal.iterateViewBulk).to.throw 'Iterator parameter required'

                frugal.iterateViewBulk undefined, undefined, undefined, undefined, (err) ->
                    expect(err).to.exist
                    expect(err.message).to.equal 'Bad input parameters'

                    mockNano = {}
                    frugal.iterateViewBulk mockNano, undefined, undefined, undefined, (err) ->
                        expect(err).to.exist
                        expect(err.message).to.equal 'Bad input parameters'

                        frugal.iterateViewBulk mockNano, 'design', undefined, undefined, (err) ->
                            expect(err).to.exist
                            expect(err.message).to.equal 'Bad input parameters'
                            done()

            it 'bulk updates docs', (done) ->
                nocks = helpers.startNocking '/fixtures/iterateViewBulk.1.json'

                docs = []
                _.each [1..100], (index) ->
                    docs.push { _id: '5.' + index, type: 'test', 'index': index }

                frugal.overwriteBulk helpers.database, docs, (err, result) ->
                    expect(err).to.not.exist
                    expect(result).to.exist
                    expect(_.keys(result.revs).length).to.equal docs.length

                    helpers.database.insert {
                        views:
                            view:
                                map: (doc) ->
                                    if(doc.type == 'test' and doc.index % 2 == 0)
                                        emit([doc.index])
                    }, '_design/test', (err, body) ->
                        # We should received half of the docs due to the "doc.index % 2 == 0" mapping.
                        docCount = 0
                        frugal.iterateViewBulk helpers.database, 'test', 'view', { limit: 15, include_docs: true }, (err, rows, next) ->
                            expect(err).to.not.exist
                            expect(rows).to.exist
                            docCount += rows.length
                            _.each rows, (row) ->
                                expect(row?.doc.index % 2 == 0).is.true
                            return next() if next and not _.isEmpty(rows)

                            helpers.stopNocking nocks
                            expect(docCount).to.equal docs.length / 2
                            done()
