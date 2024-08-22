import time


class ErrorHandler:
    """
    This is the service for your Error Handling
    """

    def __init__(self) -> None:
        pass

    @staticmethod
    def process_request(ch, method, properties, body):
        print(f" [x] Error Handler Received {body.decode()}")
        time.sleep(body.count(b"."))
        print(" [x] Done")
        ch.basic_ack(delivery_tag=method.delivery_tag)
