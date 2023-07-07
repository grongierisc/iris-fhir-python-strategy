import abc

class Strategy(object):
    """
    """
    __metaclass__ = abc.ABCMeta

    @abc.abstractmethod
    def on_get_capability_statement(self,capability_statement:dict)-> dict:
        """
        on_after_get_capability_statement is called after the capability statement is retrieved.
        param capability_statement: the capability statement
        return: None
        """
