object template simple;

# mock pkg_repl
function pkg_repl = { null; };

include 'components/maui/config';

# remove the dependencies
'/software/components/maui/dependencies' = null;

"/software/components/maui/contents" = "something new\n";
