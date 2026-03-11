"""Configuration loader for Mobile target (React Native/Expo).

This module provides configuration access for the mobile target.
Configuration is loaded from jac.toml under [mobile] section.

Similar to DesktopConfig but for mobile apps.
"""
import from pathlib { Path }
import from typing { Any }
import from jaclang.project.config { JacConfig, get_config }

"""Mobile target configuration loader.

Provides access to mobile/React Native configuration
from the [mobile] section of jac.toml.
"""
class MobileConfig {
    has project_dir: Path | None = None,
        _config: dict[str, Any] | None = None,
        _jac_config: JacConfig | None = None;

    def init(self: MobileConfig, project_dir: Path | None = None) -> None;
    def load(self: MobileConfig) -> dict[str, Any];
    def get_mobile_config(self: MobileConfig) -> dict[str, Any];
    def get_platforms_config(self: MobileConfig) -> dict[str, Any];
    def get_features_config(self: MobileConfig) -> dict[str, Any];
    def get_eas_config(self: MobileConfig) -> dict[str, Any];
    def validate(self: MobileConfig) -> None;
    def get_default_config(self: MobileConfig) -> dict[str, Any];
    def _get_jac_config(self: MobileConfig) -> JacConfig;
}
