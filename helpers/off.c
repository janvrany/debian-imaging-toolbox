/* See https://stackoverflow.com/questions/61327011/correct-way-to-exit-init-in-linux-user-mode */
#include <unistd.h>
#include <sys/reboot.h>
int main(int argc, char *argv[]) {
  sync();
  reboot(RB_POWER_OFF);
}
