# Click-based CLI entry point (replaces bin/ldd-setup)

from . import ProxyDetector
from . import EnvParser
from . import SetupWorkflow

import click

@click.group()
def main():
	"""Local Docker Domains CLI - Smart proxy management."""
	pass

@main.command()
@click.option('--config', default='.env.local', help='Configuration file')
