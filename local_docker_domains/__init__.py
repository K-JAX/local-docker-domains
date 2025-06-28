"""
Local Docker Domains - Smart proxy management for Docker development environments.

This package provides intelligent proxy detection, conflict resolution, and automate domain management for local Docker development setups.
"""

__version__	= "0.1.0"
__author__ 	= "Kevin Garubba"
__email__ 	= "kevingarubba@gmail.com"

# import main classes for easier access
from .config.env_parser import EnvParser
from .proxy.detector import ProxyDetector
from .orchestrator.setup_workflow import SetupWorkflow

# define what gets imported with "from local_docker_domains import *"
__all__ = [
	"EnvParser",
	"ProxyDetector",
	"SetupWorkflow",
]

# package-level constants
DEFAULT_CONFIG_FILES = ['.env.local', '.env']
SUPPORTED_PROXIES = ['haproxy', 'nginx', 'traefik']