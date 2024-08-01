---
eip: XXXX
title: Nomenclature and properties of crosschains message passing.
description: todo
author: Hadrien Croubois (@Amxx), Ernesto García (@ernestognw), Francisco Giordano (@frangio)
discussions-to: toto
status: Draft
type: Standards Track
category: ERC
created: 2024-08-01
---

## Abstract

The following standard focus on providing an unambiguous name to the different elements involved in cross-chain
communication, and defining some properties that these elements may or may not have. This is preparation work for a
standard crosschain communication interface.

## Motivation

todo

## Specification

### Definitions:

#### Source chain

todo

#### Requester

todo

#### Destination chain

todo

#### Target

todo

#### Payload

todo

#### Message

todo

#### Forwarder

todo

#### Gateway

todo


### Properties

#### Validity

A payload SHOULD only be executed on the target if the message was correctly submited by the requester.

Note: This is a basic security property that all crosschain systems SHOULD have.

#### Non-Replayability

A message SHOULD be succesfully executed on the target at most one time.

Note: This is a basic security property that all crosschain systems SHOULD have.

#### Retriability

A message's execution CAN be retried multiple time.

Note: When combined with *Non-Replayability*, this property allows the message execution to be retried multiple time in case the execution failled, with the guarantee that the meesage will not be successfully exected more that once. This process can be used to achieve *eventual Liveness*.

#### Ordered Execution

Messages SHOULD be executed in the same order as they were submitted

Note: Most crosschain systems do NOT have this property. In general, this property may not be desirable as it could lead to DoS.

Note: A system that doesn't have this property is said to supports *Out-of-order Execution*

#### Duplicability

A requester SHOULD be able to send the same payload to the same target multiple times. Each request should be seen as a different message.

Note: when combined with *Non-Replayability*, each submission will be executed at most once, meaning that a payload will be executed on the target at most N times, with N the number of times it was submitted by the requester.

#### Liveness

A message that was submitted MUST be executed.

A weaker version of this property is *Eventual Liveness*: A message that was sumbitted SHOULD eventually be exectued, potentially after some external intervention.

Note: *Eventual Liveness* can be achieved through *Retriability*.

#### Observability

An observer SHOULD be able track the status of a message.

Note: This property may be available with restrictions on who the observer is. For example, a system may provide observability to offchain observers through an API/explorer, but at the same time not provide observability to the requester if the status of the message is not tracked on the source chain.

## Rationale

TODO

## Security Considerations

N/A

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
