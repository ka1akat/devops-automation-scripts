# Apache Kafka with Docker Compose — topics, producers and consumers (CLI)
- Create topic `saturday-again` using CLI

      docker exec -it broker01 kafka-topics --bootstrap-server localhost:9092 --create --topic saturday-again --partitions 1 --replication-factor 1

  The Kafka CLI tools live inside the broker container, so I ran them with `docker exec`.
  `localhost:9092` works because the command runs inside `broker01`, where Kafka listens on port 9092.
  One partition and replication factor 1, because the cluster has only one broker.
  Checked the result with `--describe` and in Kafka UI (Topics: 1, Partitions: 1).
- Create a producer and send a JSON message

      docker exec -it broker01 kafka-console-producer --bootstrap-server localhost:9092 --topic saturday-again
      > {"event": "motivation_status", "day": "Saturday", "message": "Motivation level: Saturday afternoon. Status: non-existent.", "timestamp": "2026-11-14 17:30:00"}

  The console producer sends every line as a separate message, so the JSON was pasted as one line.
  The message was sent without a key. In Kafka UI it appears in partition 0 with offset 0.
- Create a consumer and read the message twice

      docker exec -it broker01 kafka-console-consumer --bootstrap-server localhost:9092 --topic saturday-again --group group-a --from-beginning

  1. First run: the message was printed (`Processed a total of 1 messages`).
  2. Second run with the same group: nothing was printed. The group had already committed
     offset 0, and `--from-beginning` only works when the group has no committed offset.
  3. Reset the group's offset to the beginning (the consumer must be stopped first):

         docker exec -it broker01 kafka-consumer-groups --bootstrap-server localhost:9092 --group group-a --topic saturday-again --reset-offsets --to-earliest --execute

  4. Third run with the same group: the message was printed again.

  Messages are not deleted after reading (they stay until retention expires),
  so the same message can be read again by moving the group's offset back.

 - Read the same message with two consumers and explain the result

  I opened two terminals and ran two consumers at the same time.

  **Case 1: both consumers in the same group**

      docker exec -it broker01 kafka-console-consumer --bootstrap-server localhost:9092 --topic saturday-again --group group-shared --from-beginning

  The message appeared in only one terminal. The topic has one partition, and inside one group
  a partition can be read by only one consumer, so the second consumer got no partition and stayed idle.
  Checked with:

      docker exec -it broker01 kafka-consumer-groups --bootstrap-server localhost:9092 --describe --group group-shared --members

  **Case 2: consumers in different groups**

      docker exec -it broker01 kafka-console-consumer --bootstrap-server localhost:9092 --topic saturday-again --group group-x --from-beginning
      docker exec -it broker01 kafka-console-consumer --bootstrap-server localhost:9092 --topic saturday-again --group group-y --from-beginning

  The message appeared in both terminals. Each group has its own committed offset,
  so different groups read the topic independently and each one gets every message.
  `--describe --group group-x` shows CURRENT-OFFSET 1, LOG-END-OFFSET 1, LAG 0.

  **Answer:** within one consumer group a message is processed by only one consumer
  (consumers share the partitions). Different consumer groups each receive all messages.
  Adding more consumers than partitions to a group does not help: the extra consumers stay idle.

  - Delete the topic 

      docker exec -it broker01 kafka-topics --bootstrap-server localhost:9092 --delete --topic saturday-again
      docker exec -it broker01 kafka-topics --bootstrap-server localhost:9092 --list