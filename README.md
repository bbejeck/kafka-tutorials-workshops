# Kafka Tutorial Workshops

Code supporting meetup workshops based on [Kafka Tutorials](https://kafka-tutorials.confluent.io/).


## Introduction

This workshop is based on the [scheduling operations](https://kafka-tutorials.confluent.io/kafka-streams-schedule-operations/kstreams.html) Kafka Tutorial.  

### Workshop Steps

#### 1. How do you schedule arbitrary operations in Kafka Streams

Kafka Streams defines the high level DSL and the Processor API.  While requiring a little more work on the developer's part, the Processor API provides the most flexibility for developing a Kafka Streams application.  You create the custom stream processor by implementing the `Processor` interface.  The `Processor` interface provides access to the `ProcessorContext` object via the `Procssor#init()` method.  

The `ProcessorContext` provides the ability to schedule execution of arbitary code inside the `Processor` with the `ProcessorContext#schedule()` method.  But what if you're using the DSL? Well that's the point of our workshop today, so let's go over to the [scheduling operations](https://kafka-tutorials.confluent.io/kafka-streams-schedule-operations/kstreams.html) tutorial for a quick introduction.

#### 2. Provision a new ccloud-stack on Confluent Cloud

This part assumes you have already set-up an account on [Confluent CLoud](https://confluent.cloud/) and you've installed the [Confluent Cloud CLI](https://docs.confluent.io/ccloud-cli/current/install.html). We're going to use the `ccloud-stack` utility to get everything set-up to work along with the workshop.  

A copy of the [ccloud_library.sh](https://github.com/confluentinc/examples/blob/latest/utils/ccloud_library.sh) is included in this repo and let's run this command now:

```
source ./ccloud_library.sh
```

Then let's create the stack of Confluent Cloud resources:

```
CLUSTER_CLOUD=aws
CLUSTER_REGION=us-west-2
ccloud::create_ccloud_stack
```

NOTE: Make sure you destroy all resources when the workshop concludes.

The `create` command generates a local config file, `java-service-account-NNNNN.config` when it completes. The `NNNNN` represents the service account id.  Take a quick look at the file:

```
cat stack-configs/java-service-account-*.config
```

You should see something like this:

```
# ENVIRONMENT ID: <ENVIRONMENT ID>
# SERVICE ACCOUNT ID: <SERVICE ACCOUNT ID>
# KAFKA CLUSTER ID: <KAFKA CLUSTER ID>
# SCHEMA REGISTRY CLUSTER ID: <SCHEMA REGISTRY CLUSTER ID>
# ------------------------------
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
bootstrap.servers=<BROKER ENDPOINT>
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<API KEY>" password="<API SECRET>";
basic.auth.credentials.source=USER_INFO
schema.registry.basic.auth.user.info=<SR API KEY>:<SR API SECRET>
schema.registry.url=https://<SR ENDPOINT>
```

We'll use these properties for connecting to CCloud from a local connect instance and from the Kafka Streams application.  We'll get to that in just a minute.

Now that we have the cloud stack resources in place, let's create two topics we'll need to use during the workshop

```
ccloud kafka topic create login-events
ccloud kafka topic create output-topic
```

#### 3. Docker and Datagen setup

In the tutorial, we used docker to provide the Kafka broker (and ZooKeeper), Schema Registy, and Kafka Connect.  We also use the [Kafka Connect Datagen](https://www.confluent.io/hub/confluentinc/kafka-connect-datagen) to create mock data to drive the application.  In our workshop CCloud provides all the infrastructure we need.  Although the datagen connector is available as a fully-managed connector on Confluent Cloud, you need to use one of provided datagen schemas.  Today we're going to provide a custom schema, so we'll still use docker to run connect locally, but generate data to the brokers on Confluent Cloud created by the `ccloud-stack`.

The included `docker-compose.yml` file is parameterized to use the properties contained in the `java-service-account` config file.  Docker compose allows you to provide an `env` file for parameter substitution, but docker can't parse the properties in the config file due to `.` notation.  So we'll run a script to format the properties into a format we can use with docker compose.

Run the following command:

```
./replace-docker-vars.sh
```

This command produces a file named `docker-compose-ccloud-vars.env` containing the properties in a docker `env` compatible format.


Now let's go ahead and start the datagen connect container now with this command:

```
docker-compose --env-file docker-compose-ccloud-vars.env up -d
```

Next, we'll wait about 60 seconds for the datagen connect container to get fully running, then we'll execute command to start generating data to the CCloud brokers:

```
curl -i -X PUT http://localhost:8083/connectors/datagen_local_01/config \
     -H "Content-Type: application/json" \
     -d '{
            "connector.class": "io.confluent.kafka.connect.datagen.DatagenConnector",
            "key.converter": "org.apache.kafka.connect.storage.StringConverter",
            "kafka.topic": "login-events",
            "schema.filename": "/schemas/datagen-logintime.avsc",
            "schema.keyfield": "userid",
            "max.interval": 1000,
            "iterations": 10000000,
            "tasks.max": "1"
        }'
```

You should see something like this indicating a successful start:

```
HTTP/1.1 200 OK
Date: Thu, 20 Aug 2020 20:15:22 GMT
Content-Type: application/json
Content-Length: 441
Server: Jetty(9.4.24.v20191120)

{"name":"datagen_local_01","config":{"connector.class":"io.confluent.kafka.connect.datagen.DatagenConnector","key.converter":"org.apache.kafka.connect.storage.StringConverter","kafka.topic":"login-events","schema.filename":"/schemas/datagen-logintime.avsc","schema.keyfield":"userid","max.interval":"1000","iterations":"10000000","tasks.max":"1","name":"datagen_local_01"},"tasks":[{"connector":"datagen_local_01","task":0}],"type":"source"}
```

#### 4. Build the model object

Now we need to build the model object based on the AVRO schema contained in the `src/main/avro` directory - `logintime.avsc`

Here's the schema
```
{
  "namespace": "io.confluent.developer.avro",
  "type": "record",
  "name": "LoginTime",
  "fields": [
    {"name": "logintime", "type": "long" },
    {"name": "userid", "type": "string" },
    {"name": "appid", "type": "string" }
  ]
}
```

The code contains a `build.gradle` file used to run a few of workshop  commands.

First we need to grab the Gradle wrapper:

```
gradle wrapper
```

Then run 

```
./gradlew build
```
to generate the Java code based on the schema


#### 5. Properties setup, build, and run the Kafka Streams application

Earlier in the workshop when you created the `ccloud-stack` a local config file `java-service-account-NNNNN.config` was created as well.  You now need to add the contents of that config file to the properties the Kafka Streams app will use.  To add the configs run the following command:

```
cat stack-configs/java-service-account* >> configuration/dev.properties
```
You should see something like this (without the brackets and actual values instead)

```

application.id=kafka-streams-schedule-operations


input.topic.name=login-events
output.topic.name=output-topic

# ENVIRONMENT ID: <ENVIRONMENT ID>
# SERVICE ACCOUNT ID: <SERVICE ACCOUNT ID>
# KAFKA CLUSTER ID: <KAFKA CLUSTER ID>
# SCHEMA REGISTRY CLUSTER ID: <SCHEMA REGISTRY CLUSTER ID>
# ------------------------------
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
bootstrap.servers=<BROKER ENDPOINT>
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="<API KEY>" password="<API SECRET>";
basic.auth.credentials.source=USER_INFO
schema.registry.basic.auth.user.info=<SR API KEY>:<SR API SECRET>
schema.registry.url=https://<SR ENDPOINT>
```

Now with the configs in place, we can start the application. To build the application and create a jar file to run the Kafka Streams app execute the following:

```
./gradlew shadowJar
```

Now start the Kafka Streams application by executing:

```
java -jar build/libs/kafka-streams-schedule-operations-standalone-0.0.1.jar configuration/dev.properties
```

We'll see some log statements scroll across the screen, then we should see some print statements from the application when the `wallclock punctuator` fires.

After we let this run for a little bit, let's stop the app with a `CTRL+C` command.

#### 6. Review the output

Now let's use the `ccloud cli` one more time to view some of the output from the Kafka Streams application

```
ccloud kafka topic consume --print-keys --from-beginning
```

#### 7. Cloud UI Demo

Now we'll go to [Confluent Cloud](https://login.confluent.io/]) and login. Then we'll take a look at the CCloud UI and go over the available information. 


#### 8. Testing - "Look Ma no hands!"

Last, but not least, we should take a couple of minutes to talks about testing. Let's take this 
opportunity to shut down your `ccloud-stack` resources.  Run the following command:

```
ccloud::destroy_ccloud_stack $SERVICE_ACCOUNT_ID
```
The `SERVICE_ACCOUNT_ID` was generated when you created the `ccloud-stack`.  This would also be a good time to shut down the connect container by running

```
docker-compose down
```

So now we'll see how you can test locally, without the need for any of the resources we used in our example.  But our test code uses the same Kafka Streams application as written.  Run this command to test our code:

```
./gradlew test
```

The test should pass.  It's possible to unit-test with the exact Kafka Streams application because we'er using the [ToplogyTestDriver](https://docs.confluent.io/5.5.0/streams/developer-guide/test-streams.html#testing-a-streams-application) and mocked version of Schema Registry.  Let's take a look at the test properites.  You'll see the Schema Registry endpoint supplied as 

```
schema.registry.url=mock://kafka-streams-schedule-operations-test
```

This mocks a live Schema Registry instance and allows us to use the exisiting code as is, we only need to swap out the values in the properties file.


#### 9. Clean Up

If you haven't done so already, now is a good time to shut down all the resources we've created and started.  Because your Confluent Cloud cluster is using real cloud resources and is billable, delete the connector and clean up your Confluent Cloud environment when you complete this tutorial. You can use Confluent Cloud CLI or Confluent UI, but for this tutorial you can use the ccloud_library.sh library again. Pass in the `SERVICE_ACCOUNT_ID` that was generated when the `ccloud-stack was` created.

First clean up the `ccloud-stack`:

```
ccloud::destroy_ccloud_stack $SERVICE_ACCOUNT_ID
```

Then shut down the connect docker container:

```
docker-compose down
```
