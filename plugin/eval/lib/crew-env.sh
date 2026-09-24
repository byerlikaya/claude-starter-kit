# Sourced, not run. The ONE bash place that still reads the pre-3.0 CSK_* names.
#
# 3.0 renamed every CSK_* variable to CREW_*. The ones a user can have set — because a README, --help, a command
# file or a message names them — keep working for the whole 3.x line: when CREW_<X> is not set at all and CSK_<X>
# is, CREW_<X> takes its value. A CREW_<X> that is set, even to 0 or empty, wins. Internal and test variables were
# renamed with no fallback. The old names go in 4.0.
#
# Builtins only (a loop of `eval`s): sourcing this costs no process, which matters in hooks on Git Bash.
for _crew_v in LANG NO_STAR NO_UPDATE_CHECK NO_BOARD GATE_LOG GATE_LOG_CMD STUDIO_TOKEN STUDIO_PEERS STUDIO_RUNTIME \
               MAX_FILE_BYTES ALLOW_SOURCE_INSTALL; do
  eval "if [ -z \"\${CREW_$_crew_v+x}\" ] && [ -n \"\${CSK_$_crew_v+x}\" ]; then CREW_$_crew_v=\"\$CSK_$_crew_v\"; export CREW_$_crew_v; fi"
done
unset _crew_v
