"""
公共流水线参数。
"""

from xflow.framework.pipeline import Pipeline


class RepoOptions(Pipeline.Options):
    """
    源码仓库参数。
    """
    repo_url: str = Pipeline.Option(desc='Repository URL.')
    revision: str = Pipeline.Option(desc='Branch, tag, or commit.')
