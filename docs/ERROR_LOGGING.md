# Error Logging System

This document describes the centralized error logging system implemented in the Blazor-Hosting project.

## Overview

The error logging system provides a consistent way to log errors, warnings, informational messages, and debug output across all bash scripts. Logs are automatically written to a central location for easy troubleshooting.

## Log Location

Logs are stored at:
- **Primary**: `~/.config/ghostly-hosting/logs/error.log`
- **Fallback**: `/tmp/ghostly-hosting-logs/error.log` (if config directory is not writable)

## Log Functions

### log_error(context, message, [exit_code])
Logs error messages with optional exit code.

```bash
log_error "function_name" "Failed to connect to API" 1
```

### log_warning(context, message)
Logs warning messages for non-critical issues.

```bash
log_warning "validation" "Missing optional parameter"
```

### log_info(context, message)
Logs informational messages for audit trail.

```bash
log_info "deployment" "Application deployed successfully"
```

### log_debug(context, message)
Logs debug messages (only when DEBUG_MODE=true).

```bash
log_debug "parser" "Processing line 42"
```

## Log Format

Each log entry follows this format:
```
[YYYY-MM-DD HH:MM:SS] [LEVEL] [CONTEXT] message
```

Example:
```
[2025-01-15 10:30:45] [ERROR] [validate_token] Authentication failed with status 401
[2025-01-15 10:30:45] [ERROR] [validate_token] Exit code: 1
```

## Debug Mode

Enable debug logging by setting the DEBUG_MODE environment variable:

```bash
export DEBUG_MODE=true
./start.sh
```

When DEBUG_MODE is enabled:
- Debug messages are logged to the error log file
- Debug messages are also printed to stderr
- All other log levels also print to stderr

## Using in Your Scripts

### Option 1: Direct Logging (if log.sh is sourced)

```bash
source ./lib/log.sh

log_error "my_function" "Something went wrong"
log_info "my_function" "Operation completed"
```

### Option 2: Safe Logging (recommended in lib/ scripts)

The `_safe_log()` helper in common.sh checks if logging functions exist before calling them:

```bash
source ./lib/common.sh

_safe_log error "my_function" "Something went wrong"
_safe_log info "my_function" "Operation completed"
```

This is safer because it won't fail if log.sh hasn't been sourced yet.

## Integration with Existing Code

All major functions in the following modules now include error logging:

### lib/common.sh
- `load_env_once()` - Logs warnings when .env file is missing
- `is_valid_ipv4()` - Debug logs for invalid IP formats
- `load_server_ip_once()` - Info logs for successful IP retrieval
- `set_swap()` - Info/error logs for swap configuration
- `update_server()` - Info/error logs for package updates
- `get_project_root()` - Error logs if root cannot be determined

### lib/upcloud.sh
- `validate_upcloud_token()` - Info/error logs for token validation
- `_get_upcloud_server_uuid_by_ip()` - Info/error logs for UUID resolution

### lib/github.sh
- `validate_github_token()` - Info/error logs for token validation
- `check_github_env_vars()` - Error logs for missing environment variables
- `clone_repository()` - Info/error logs for repository operations

## Viewing Logs

### View recent errors
```bash
tail -f ~/.config/ghostly-hosting/logs/error.log
```

### View all errors today
```bash
grep "$(date +%Y-%m-%d)" ~/.config/ghostly-hosting/logs/error.log
```

### View only ERROR level
```bash
grep "\[ERROR\]" ~/.config/ghostly-hosting/logs/error.log
```

### View logs for specific context
```bash
grep "\[validate_token\]" ~/.config/ghostly-hosting/logs/error.log
```

## Best Practices

1. **Always provide context**: Use function name or module name as context
   ```bash
   log_error "deploy_app" "Failed to start service" 1
   ```

2. **Be descriptive**: Include relevant details in messages
   ```bash
   log_error "clone_repo" "Failed to clone https://github.com/user/repo: timeout"
   ```

3. **Use appropriate log levels**:
   - ERROR: Something failed that prevents normal operation
   - WARNING: Something unexpected but operation can continue
   - INFO: Normal operational messages (deployments, config changes, etc.)
   - DEBUG: Detailed diagnostic information

4. **Log before critical operations**:
   ```bash
   log_info "backup" "Starting backup of $APP_DIR"
   if ! perform_backup "$APP_DIR"; then
     log_error "backup" "Backup failed for $APP_DIR" $?
     return 1
   fi
   log_info "backup" "Backup completed successfully"
   ```

5. **Include error codes when available**:
   ```bash
   if ! curl -f "$URL" >/dev/null 2>&1; then
     log_error "api_call" "curl failed with exit code $?" $?
   fi
   ```

## Testing

The logging system includes comprehensive unit tests:

```bash
# Run all logging tests
bash test/log_tests.sh

# Run error logging integration tests
bash test/common_error_logging_tests.sh
```

## Troubleshooting

### Logs not appearing
1. Check if log directory exists and is writable
2. Verify log.sh is being sourced
3. Check if logging functions are defined: `declare -f log_error`

### Debug logs not showing
1. Ensure DEBUG_MODE is set: `echo $DEBUG_MODE`
2. Set it explicitly: `export DEBUG_MODE=true`

### Permission issues
If the primary log directory is not writable, the system automatically falls back to `/tmp/ghostly-hosting-logs/`. Check there if logs are missing from the primary location.

## Future Enhancements

Potential improvements for the logging system:

- Log rotation (automatically archive old logs)
- Log levels filtering via configuration
- Structured logging (JSON format option)
- Remote logging support (syslog, external services)
- Performance metrics logging
- Log analysis scripts
