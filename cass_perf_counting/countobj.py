import argparse
import datetime
import random, string

from cassandra.cluster import Cluster
from cassandra import ConsistencyLevel
from cassandra.query import SimpleStatement
from cassandra.cluster import ExecutionProfile
from cassandra.policies import WhiteListRoundRobinPolicy

def randomword(length):
   letters = string.ascii_lowercase
   return ''.join(random.choice(letters) for i in range(length))


def arguments():
    parser = argparse.ArgumentParser(description='Statistics script')
    parser.add_argument('-i', '--host', type=str, required=True, help="IP address for Cassandra")
    parser.add_argument('-k', '--keyspace', type=str, required=True, help="Keyspace to query")
    parser.add_argument('-t', '--table', type=str, required=False, help="Table to query - defaults to api_portal_portalapi", default='api_portal_portalapi')
    parser.add_argument('-f', '--fetch', type=int, required=False, help="fetch size", default='5000')
    args = parser.parse_args()

    casshost = args.host
    ks = args.keyspace
    tbl = args.table
    fetch = args.fetch
    return casshost, ks, tbl, fetch


def insert_blob(session, ks, tbl):
    blob_insert = "INSERT INTO " + ks + "." + tbl + "(key, blob) VALUES (?, ?) ;"
    blobins_prep = session.prepare(blob_insert)
    blobins_prep.consistency_level = ConsistencyLevel.LOCAL_QUORUM
    return blobins_prep
    

def gateway_insert(session, ks, tbl):
    blobins_prep = insert_blob(session, ks, tbl)

    for i in range (0, 100000):
        genblob = randomword(10000)
        blobins_bind = blobins_prep.bind((i, genblob))
        session.execute(blobins_bind)
        if i%1000 == 0:
            print( "Written " + str(i) + " records so far, time now " + str(datetime.datetime.now()) )


def gateway_query(session, ks, tbl, fetch):
    row_count = 0
    row_sizes = []
    row_keys = []

    portalquery = SimpleStatement("select key from " + ks + "." + tbl + ";",
            consistency_level=ConsistencyLevel.LOCAL_QUORUM, fetch_size=fetch)
    portalquerywithblob = SimpleStatement("select key, blob from " + ks + "." + tbl + ";",
            consistency_level=ConsistencyLevel.LOCAL_QUORUM, fetch_size=fetch)
    portalcount = SimpleStatement("select count(*) as count from " + ks + "." + tbl + ";",
            consistency_level=ConsistencyLevel.LOCAL_QUORUM, fetch_size=fetch)

    query_start = datetime.datetime.now()

    try:    
        rows = session.execute(portalquerywithblob)
        for row in rows:
            row_count += 1
            row_keys.append(row.key)
            #print(row)
            # TODO: define how to calculate the full row size. Query based on SELECT key at this time.
            if row.blob is not None: 
                row_size = len(row.blob)
                row_sizes.append(row_size)
    except Exception as e:
            print(e)

    query_end = datetime.datetime.now()
    query_diff = query_end - query_start
    print("# SELECT #\nRow count:", row_count)
    print("Query timing with fetch " + str(fetch) + ": " + str(query_diff))

    count_start = datetime.datetime.now()

    print("# COUNT #")

    try:
        ### Sync query
        result = session.execute(portalcount)
        ### Async query
        # future = session.execute_async(portalcount, trace=True)
        # result = future.result()
        # trace = future.get_query_trace()
        # for e in trace.events:
        #     print(e.source_elapsed, e.description)

        for row in result:
            print("Row count:" + str(row.count))
    except Exception as e:
            print(e)

    count_end = datetime.datetime.now()
    count_diff = count_end - count_start
    print("Count timing with fetch " + str(fetch) + ": " + str(count_diff))

    statistics = calculate_row_statistics(row_sizes)
    print("Average row size:", statistics["average_size"])
    print("Max row size:", statistics["max_size"])
    print("Min row size:", statistics["min_size"])

def calculate_row_statistics(row_sizes):
    if not row_sizes:
        return {
            "average_size": 0,
            "max_size": 0,
            "min_size": 0,
            "row_count": 0
        }
    
    row_count = len(row_sizes)
    average_size = sum(row_sizes) / row_count
    max_size = max(row_sizes)
    min_size = min(row_sizes)

    return {
        "average_size": average_size,
        "max_size": max_size,
        "min_size": min_size,
        "row_count": row_count
    }

def main():
    host, ks, tbl, fetch = arguments()

    profile_long = ExecutionProfile(request_timeout=30)
    cluster = Cluster([host], port=9042, execution_profiles={'long': profile_long})
    #cluster = Cluster([host], port=9042)

    session = cluster.connect()
    gateway_insert(session, ks, tbl)
    gateway_query(session, ks, tbl, fetch)
    
if __name__ == "__main__":
    main()


# CREATE TABLE romain.api_portal_portalapi (
#     key text PRIMARY KEY,
#     "basePath" text,
#     blob text,
#     consumes text,
#     "createdBy" text,
#     "createdOn" text,
#     description text,
#     "hasOriginalDefinition" text,
#     hash text,
#     id text,
#     "importUrl" text,
#     integral text,
#     models text,
#     name text,
#     "organizationId" text,
#     produces text,
#     properties text,
#     "resourcePath" text,
#     "serviceType" text,
#     summary text,
#     type text,
#     version text
# );
# CREATE TABLE romain.api_portal_portalapimethod (
#     key text PRIMARY KEY,
#     "apiId" text,
#     blob text,
#     description text,
#     id text,
#     name text,
#     path text,
#     properties text,
#     summary text,
#     verb text
# );