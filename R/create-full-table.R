
## This R Script produces the entire table shown in the
## "Using gt, gtExtras and openair to present air quality monitoring data"
## tutorial. For more details, please look to the tutorial found at:
#
# https://rpubs.com/JackDavison/gt-openair

## NB: No external data is required, but you may need to install the tidyverse, gt and openair
## from CRAN, and gtExtras using:
#
# remotes::install_github("jthomasmock/gtExtras")

library(tidyverse)
library(openair)
library(gt)
library(gtExtras)

data = mydata |>
  mutate(year = lubridate::year(date)) |> 
  filter(year == 2003) |> 
  pivot_longer(nox:pm25, names_to = "species", values_to = "conc") |> 
  mutate(species = factor(species, c("co", "nox", "no2", "o3", "so2", "pm25", "pm10"))) |> 
  arrange(species)

averages = data |> 
  group_by(species) |> 
  summarise(p25 = quantile(conc, .25, na.rm = T),
            median = median(conc, na.rm = T),
            mean   = mean(conc, na.rm = T),
            p75 = quantile(conc, .75, na.rm = T),
            max    = max(conc, na.rm = T),
            missing = sum(is.na(conc)) / n()
  )

spark = data |>
  timeAverage(avg.time = "month", type = "species") |> 
  group_by(species) |> 
  summarise(trend = list(conc))

all_data = left_join(averages, spark) |> 
  mutate(polrose = NA,
         polplot = NA)

# Function to tabulate plots 

openair_image = function (plot_object, height){
  if (is.numeric(height)) {
    height <- paste0(height, "px")
  }
  if (inherits(plot_object, "trellis")) {
    plot_object <- list(plot_object)
  }
  invisible(vapply(seq_along(plot_object), FUN.VALUE = character(1),
                   USE.NAMES = FALSE, FUN = function(x) {
                     filename <- paste0("temp_openair_", formatC(x, width = 4,
                                                                 flag = "0"), ".png")
                     
                     lattice::trellis.device(device = "png", filename = filename)
                     print(plot_object[[x]])
                     dev.off()
                     
                     on.exit(file.remove(filename))
                     local_image(filename = filename, height = height)
                   }))
}

# List of plots

data_plots = data |> 
  nest_by(species) |>
  mutate(polrose = list(pollutionRose(data, pollutant = "conc")$plot),
         polplot = list(polarPlot(data, pollutant = "conc")$plot)) |> 
  arrange(species)

# Pre-format table data

tab_data = all_data |>
  mutate(
    name = case_when(
      species == "co" ~ "Carbon Monoxide",
      species == "nox" ~ "Oxides of Nitrogen",
      species == "no2" ~ "Nitrogen Dioxide",
      species == "o3"  ~ "Ozone",
      species == "so2" ~ "Sulfur Dioxide",
      species == "pm25" ~ "Particulate Matter",
      species == "pm10" ~ ""
    ),
    species = case_when(
      species == "co" ~ "CO",
      species == "nox" ~ "NO<sub>x</sub>",
      species == "no2" ~ "NO<sub>2</sub>",
      species == "o3"  ~ "O<sub>3</sub>",
      species == "so2" ~ "SO<sub>2</sub>",
      species == "pm25" ~ "PM<sub>2.5</sub>",
      species == "pm10" ~ "PM<sub>10</sub>"
    )) |> 
  relocate(name, .before = species)

# Tabulate

our_table = gt(tab_data) |> 
  
  # Set theme as ESPN
  gt_theme_espn() |> 
  
  # Format columns
  fmt_number(columns = where(is.numeric), n_sigfig = 3, drop_trailing_zeros = T) |> 
  fmt_percent(columns = missing) |> 
  fmt_markdown(columns = species) |>
  
  # Column labels, widths, and alignments
  cols_label(name = "Species Name",
             species = "Formula",
             polrose = "Poll. Rose",
             polplot = "Polar Plt.") |> 
  cols_width(c(p25, median, mean, p75, max, missing) ~ px(50),
             name ~ px(120)) |> 
  cols_align(align = "left", columns = 1) |> 
  cols_align(align = "center", columns = 2) |> 
  
  # Format table (add spanners, title, footnotes, set font size, etc.)
  tab_options(table.font.size = 12) |> 
  tab_spanner(label = "Statistics", columns = p25:missing) |> 
  tab_spanner(label = "Visualisations", columns = trend:polplot) |> 
  tab_header(title = md("<b>Marylebone 2003</b> | Air Quality Monitoring Summary"),
             subtitle = md("The data contains hourly measurements of air pollutant concentrations, wind speed and wind direction collected at the Marylebone (London) air quality monitoring supersite.")) |> 
  tab_source_note(source_note = md("The data were obtained using the <code>openair</code> package.")) |> 
  tab_footnote(locations = cells_column_labels(columns = trend), 
               footnote = "Monthly average. The lowest and highest months are indicated with green and red, respectively.") |> 
  
  # Format sparkline
  gt_sparkline(
    column = trend,
    range_colors = c("chartreuse3", "red"),
    same_limit = F
  ) |> 
  
  # replace empty columns with plots
  text_transform(
    locations = cells_body(polrose),
    fn = function(x){
      map(data_plots$polrose, openair_image, height = px(70))
    }
  ) |> 
  text_transform(
    locations = cells_body(polplot),
    fn = function(x){
      map(data_plots$polplot, openair_image, height = px(70))
    }
  )
