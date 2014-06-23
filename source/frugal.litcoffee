
# Frugal Couch in Node

## Initialization

For logging and other tasks we use several external modules.

    _       = require 'lodash'
    debug   = (require 'debug') 'frugal-couch'

## Exports

### `overwriteBulk`

`overwriteBulk` is a function designed to perform bulk updating of given documents even when their revision values are out of date.

Bulk updating documents have two significant advantages over updating them one by one:

1.It's much faster as it requires only two trips to CouchDb for all the docs vs. two trips for each doc (one trip to try to update and if that fails then a new trip with corrected revision value)
2.It's much cheaper if used on DaaS like Cloudant which charge the same for bulk requests and non-bulk requests (so if you have 10,000 docs that you need to update you'll be charged for 2 requests and not for 20,000 requests)

Bulk updating shouldn't be used always unless you are absolutely certain that nothing else is updating your database. It can be very useful even in multi-client databases as some types of documents may considered to be stable and depending only on external values (e.g. importing Facebook Graph data)

This function accepts three parameters:

1.`database`: [`nano`](https://github.com/dscape/nano) database object (or an object with equivalent semantics) used to access the database

2.`docs`: an array of documents that need to be bulk-updated

3.`callback`: function with `(err, result)` signature. `result` is an object containing `inserted`, `updated`, `resurected` arrays and `revs` and `errors` objects. The three arrays hold the ids of inserted, updated and resurected documents (previously deleted and now re-inserted) while the two objects have properties matching document ids and their latest revisions or CouchDb generated errors respectively. `callback` is always invoked asynchronously

    exports.overwriteBulk = (database, docs, callback) ->

        getResultObject = (inserted, updated, resurected, revs, errors) ->
            return {
                inserted:   inserted or []
                updated:    updated or []
                resurected: resurected or []
                revs:       revs or {}
                errors:     errors or {}
            }

All parameters must be valid.

        if not _.isFunction(callback)
            throw new Error('Callback parameter required')

        if not database or not _.isArray(docs)
            debug 'Bad input parameters passed to overwriteBulk function'
            return process.nextTick ->
                callback new Error('Bad input parameters')

        if _.isEmpty(docs)
            return process.nextTick ->
                callback null, getResultObject()

Since CouchDb doesn't support bulk updating without _rev we first retreive all the revision numbers of all given docs. That allows us to update the _rev values of the docs we are supposed to update and only then do we bulk upload the docs.

        debug 'Overwritting', docs.length, 'docs in bulk'

Construct the map of doc ids with doc objects so that we can both access just the list of doc ids as well as be able to later update the revisions of docs in `O(n log n)`.

        idDocsMap = {}
        _.each docs, (doc) ->
            idDocsMap[doc._id] = doc

Query the database for the revisions of all the docs. Once we have the revisions we will update the docs and then bulk upload them.

        debug 'Fetching doc revisions'

        return database.fetch_revs { keys: Object.keys idDocsMap }, (err, revisions) ->
            return callback err if err
            return callback new Error 'Invalid document revisions returned.' unless revisions

Update the revisions of the documents with the revision values we got from the server. The conditions to update the revision value are:

1. Row object exists and has both value and id properties.
2. The document with the same id already exists in the db (even if it's deleted as CouchDb keeps *all* docs forever).

            debug 'Updating docs with correct revisions'

            inserted = []
            updated = []
            resurected = []
            _.each revisions.rows, (row) ->

We update the doc if and only if everything is correct (doc id exists among our docs, rev was correctly returned from the server, doc isn't deleted on the server, etc.)

                return debug 'Bad revision item received' unless row

If the row error is `not_found` then this document has a new ID in the database.

                docId = row.key
                return debug 'Bad document id received', docId unless docId

                if row.error
                    if row.error == 'not_found'
                        # We delete the revision just in case there is one as CouchDb will otherwise reject it.
                        delete idDocsMap[docId]._rev
                        inserted.push docId
                    else
                        debug 'Error received', row.error
                    return

                return debug 'Bad revision value received' unless row.value?.rev
                doc = idDocsMap[docId]
                return debug 'Bad document id', docId unless doc

If the document with the same id already existed but was deleted then CouchDb will expect from us to *not* pass revision number. But if it exists right now (it hasn't been deleted) then we have to pass its current revision number (freshly retrieved from the database).

                if row.value.deleted
                    delete doc._rev
                    resurected.push docId
                else
                    doc._rev = row.value.rev
                    updated.push docId

After the document revs have been updated, we bulk load them and pass on the results to the given `callback`

            debug 'Inserting', inserted.length, 'docs'
            debug 'Updating', updated.length, 'docs'
            debug 'Resurecting', resurected.length, 'docs'

            database.bulk { docs: docs }, (err, body) ->
                revs = {}
                errors = {}
                _.each body, (row) ->
                    if row.ok
                        revs[row.id] = row.rev
                    else
                        errors[row.id] = {
                            id:     row.id
                            error:  row.error
                            reason: row.reason
                        }

                callback err, getResultObject(inserted, updated, resurected, revs, errors)

### `partialUpdateBulk`

`partialUpdateBulk` function performs partial updates of the documents with the given IDs.

CouchDb allows partial server-side modification of documents through its update handler feature. However, this feature doesn't work for arrays of documents and is thus too slow for massive document updates.

The alternative is to retrieve all the documents, apply the modification function to them and then bulk upload them. This is what `partialUpdateBulk` does.

This function accepts the following parameters:

1.`database`    -   `nano` database object or an object with equivalent semantics

2.`docIds`      -   the array of IDs of the documents to update

3.`partialUpdater`  -   the function accepting a single parameter (`doc` representing a database document) that does the document update and which will be invoked for each retrieved document

4.`callback`    -   function accepting `err` and `result` parameters:

 - `err`      -   error value in case of any error, falsy otherwise
 - `result`   -   object with `revs` and `errors` object properties. `revs` maps the document IDs to their post-operation revision while errors maps any CouchDb errors to document ID related to it

    exports.partialUpdateBulk = (database, docIds, partialUpdater, callback) ->

        getResultObject = (revs, errors) ->
            return {
                revs:       revs or {},
                errors:     errors or {}
            }

All parameters must be valid.

        if not _.isFunction(callback)
            throw new Error('Callback parameter required')

        if not database or not _.isArray(docIds) or not _.isFunction(partialUpdater)
            debug 'Bad input parameters passed to partialUpdateBulk function'
            return process.nextTick ->
                callback new Error('Bad input parameters')

        if _.isEmpty(docIds)
            return process.nextTick ->
                callback null, getResultObject()

To update the docs we fetch them, update them in-place and then bulk upload them again.

        debug 'Partial bulk updating', docIds.length, 'docs'

        return database.fetch { keys: docIds }, (err, body) ->
            return callback err if err
            return callback new Error 'Invalid documents returned.' if _.isEmpty(body?.rows)

            docs = []
            _.each body.rows, (row) ->
                doc = row.doc
                docs.push doc
                partialUpdater doc

            database.bulk { docs: docs }, (err, body) ->
                revs = {}
                errors = {}
                _.each body, (row) ->
                    if row.ok
                        revs[row.id] = row.rev
                    else
                        errors[row.id] = {
                            id:     row.id
                            error:  row.error
                            reason: row.reason
                        }

                callback err, getResultObject(revs, errors)

### `iterateViewBulk`

`iterateViewBulk` function is used to iterate over CouchDb views.

This function accepts the following parameters:

1.`database`    -   `nano` database object or an object with equivalent semantics

2.`designDoc`   -   the name of the design document in which the view is to be found.

3.`viewName`    -   the name of the view which will be queried.

4.`options`     -   standard CouchDb options like `startkey` and `endkey`. It also holds the number of documents in each desired iteration in its `limit` property. If it doesn't then the default batch size is 1,000 documents (completely arbitrary number). One property that this function ignores is `skip` as it's needed to perform correct and optimal iterations.

5.`iterator`    -   function accepting `err`, `docs` and `next` parameters:

 - `err`      -   error value in case of any error, falsy otherwise
 - `rows`     -   the array of view entries in the current iteration
 - `next`     -   the function to be invoked when the next iteration should be performed

    exports.iterateViewBulk = (database, designDoc, viewName, options, iterator) ->

If iterator doesn't exist, options parameter is our iterator.

        if not iterator
            iterator = options
            options = undefined

Create a clone of the given `options` so that we don't change them during iteration.

        options = _.clone(options) or {}
        options.skip = 0
        options.limit = options.limit or 1000

All parameters must be valid.

        if not _.isFunction(iterator)
            throw new Error('Iterator parameter required')

        if not database or not designDoc or not viewName or not options
            debug 'Bad input parameters passed to iterateViewBulk function'
            return process.nextTick ->
                iterator new Error('Bad input parameters')

`nextIteration` function performs all the work of querying the view, checking the results and invoking the `iterator` function.

        nextIteration = ->
            database.view designDoc, viewName, options, (err, body) ->
                return iterator err if err
                return iterator null, [] if not body or _.isEmpty(body.rows)

Increment the skip count depending on the amount of data we got in this iteration.

                options.skip = options.skip + body.rows.length

Indirect recursion call. This will invoke the `iterator` function which in turn will invoke `nextIteration` itself when it finishes processing the current batch.

                iterator null, body.rows, nextIteration

Start iteration by invoking `nextIteration` for the first time.

        nextIteration()

## License

The MIT License (MIT)

Copyright (c) 2014 Software Marbles SpA

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
