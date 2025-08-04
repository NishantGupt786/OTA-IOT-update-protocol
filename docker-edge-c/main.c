#include <stdio.h>
#include <stdlib.h>

int main() {
    FILE *fp;
    int temp;

    fp = fopen("/sys/class/thermal/thermal_zone0/temp", "r");
    if (fp == NULL) {
        perror("Failed to read temperature");
        return 1;
    }

    fscanf(fp, "%d", &temp);
    fclose(fp);

    printf("CPU Temperature: %.2f°C\n", temp / 1000.0);
    return 0;
}
